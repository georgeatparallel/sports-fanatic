defmodule SportsFanatic.Mlb do
  @moduledoc """
  MLB context — pure read paths over `mlb.scheduled_games`, `public.teams`,
  `mlb.pitcher_stats`, and `mlb.game_weather_forecast`.

  The primary public API is `todays_game_for_player/2`, which answers the
  question "does this player's team have a scheduled game on `date`?" from
  the canonical schedule table (not from `mlb.hit_predictions`, which is an
  ML output that may be empty for legitimate reasons).

  See `lib/sports_fanatic/mlb/CLAUDE.md` for the data model. Cache wrapping
  uses `sf:data:game_card:player:{uuid}:{YYYY-MM-DD}` with a null-sentinel
  (`"__none__"`) for off-days so we don't re-query Postgres on every page
  load for a player whose team isn't playing.
  """

  import Ecto.Query

  alias SportsFanatic.Cache
  alias SportsFanatic.Mlb.{Player, ScheduledGame, Team}
  alias SportsFanatic.Repo

  require Logger

  @null_sentinel "__none__"
  @eastern_offset_hours -4

  @typedoc "Compact game-card map returned to controllers/templates."
  @type game_card :: %{
          required(:scheduled_game_id) => integer(),
          required(:is_home) => boolean(),
          required(:opponent_team) => Team.t() | nil,
          required(:opponent_name) => String.t(),
          required(:venue_name) => String.t() | nil,
          required(:venue_id) => integer() | nil,
          required(:game_datetime_utc) => DateTime.t() | NaiveDateTime.t() | nil,
          required(:local_time_label) => String.t() | nil,
          required(:probable_pitcher_name) => String.t() | nil,
          required(:pitcher_record_label) => String.t() | nil,
          required(:weather_oneliner) => String.t() | nil
        }

  @doc """
  Returns a game-card map for the player's team on `date`, or `nil` when the
  team has no scheduled game that day.

  Reads through `SportsFanatic.Cache` with a null-sentinel for off-days. TTL
  expires at the next Eastern midnight via
  `DateHelper.seconds_until_eastern_midnight/0`.

  Accepts either a `%Player{}` struct (preferred — no extra DB hit) or a
  binary player id (UUID).
  """
  @spec todays_game_for_player(Player.t() | binary(), Date.t()) :: game_card() | nil
  def todays_game_for_player(player_or_id, date)

  def todays_game_for_player(%Player{team_id: nil}, %Date{}), do: nil

  def todays_game_for_player(%Player{} = player, %Date{} = date) do
    fetch_with_cache(player, date)
  end

  def todays_game_for_player(player_id, %Date{} = date) when is_binary(player_id) do
    case Repo.get(Player, player_id) do
      %Player{} = player -> todays_game_for_player(player, date)
      nil -> nil
    end
  end

  def todays_game_for_player(_, _), do: nil

  # ---------------------------------------------------------------------------
  # Cache wrapper
  # ---------------------------------------------------------------------------

  defp fetch_with_cache(%Player{id: player_id} = player, %Date{} = date) do
    key = Cache.game_card_key(player_id, date)

    case safe_cache_get(key) do
      {:hit, @null_sentinel} ->
        nil

      {:hit, raw} when is_binary(raw) ->
        case decode_card(raw) do
          {:ok, card} ->
            card

          :error ->
            # Corrupted/legacy entry — rebuild.
            load_and_cache(player, date, key)
        end

      :miss ->
        load_and_cache(player, date, key)
    end
  end

  defp safe_cache_get(key) do
    case Cache.get(key) do
      {:ok, nil} -> :miss
      {:ok, value} when is_binary(value) -> {:hit, value}
      _ -> :miss
    end
  rescue
    _ -> :miss
  end

  defp load_and_cache(%Player{} = player, %Date{} = date, key) do
    card = load_game_card(player, date)
    ttl = SportsFanatic.DateHelper.seconds_until_eastern_midnight()

    payload =
      case card do
        nil -> @null_sentinel
        %{} = c -> encode_card(c)
      end

    _ = safe_cache_set(key, payload, ttl)

    card
  end

  defp safe_cache_set(key, value, ttl) do
    Cache.set(key, value, ttl)
  rescue
    _ -> :ok
  end

  # ---------------------------------------------------------------------------
  # DB load
  # ---------------------------------------------------------------------------

  defp load_game_card(%Player{team_id: nil}, _date), do: nil

  defp load_game_card(%Player{team_id: team_id}, %Date{} = date) do
    case Repo.get(Team, team_id) do
      nil ->
        nil

      %Team{} = team ->
        case fetch_scheduled_game(team, date) do
          nil ->
            nil

          %ScheduledGame{} = sg ->
            build_card(sg, team)
        end
    end
  end

  defp fetch_scheduled_game(%Team{name: team_name}, %Date{} = date) do
    Repo.one(
      from sg in ScheduledGame,
        where:
          sg.game_date == ^date and
            (sg.home_name == ^team_name or sg.away_name == ^team_name),
        order_by: [asc: sg.game_datetime],
        limit: 1
    )
  end

  defp build_card(%ScheduledGame{} = sg, %Team{} = team) do
    is_home = sg.home_name == team.name
    opponent_name = if is_home, do: sg.away_name, else: sg.home_name
    opponent_team = lookup_team_by_name(opponent_name)

    probable_pitcher_name =
      if is_home, do: sg.away_probable_pitcher, else: sg.home_probable_pitcher

    %{
      scheduled_game_id: sg.game_id,
      is_home: is_home,
      opponent_team: opponent_team,
      opponent_name: opponent_name,
      venue_name: sg.venue_name,
      venue_id: sg.venue_id,
      game_datetime_utc: sg.game_datetime,
      local_time_label: format_et_time(sg.game_datetime),
      probable_pitcher_name: probable_pitcher_name,
      pitcher_record_label: lookup_pitcher_record(probable_pitcher_name, sg.game_date),
      weather_oneliner: lookup_weather(sg.venue_id, sg.game_datetime)
    }
  end

  defp lookup_team_by_name(nil), do: nil

  defp lookup_team_by_name(name) when is_binary(name) do
    Repo.one(from t in Team, where: t.name == ^name, limit: 1)
  end

  # ---------------------------------------------------------------------------
  # Pitcher record (best-effort)
  # ---------------------------------------------------------------------------

  # `mlb.pitcher_stats` is keyed by `pitcher_mlb_id`. The scheduled_games row
  # only has the pitcher's display name, so we go Player → external_ids.mlb_id
  # → pitcher_stats.era. When external_ids has no `mlb_id` (current prod
  # reality, see CODE-002), this returns nil and the template omits the line.
  defp lookup_pitcher_record(nil, _date), do: nil

  defp lookup_pitcher_record(name, %Date{year: season}) when is_binary(name) do
    sql = """
    SELECT ps.era
      FROM public.players pp
      JOIN mlb.pitcher_stats ps
        ON ps.pitcher_mlb_id = NULLIF((pp.external_ids->>'mlb_id'), '')::int
     WHERE pp.full_name = $1 AND ps.season = $2
     LIMIT 1
    """

    case Repo.query(sql, [name, season]) do
      {:ok, %{rows: [[era] | _]}} when not is_nil(era) -> format_era(era)
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp format_era(era) when is_float(era), do: "#{Float.round(era, 2)} ERA"
  defp format_era(era) when is_integer(era), do: "#{era}.00 ERA"

  defp format_era(%Decimal{} = era) do
    "#{Decimal.to_string(Decimal.round(era, 2))} ERA"
  end

  defp format_era(_), do: nil

  # ---------------------------------------------------------------------------
  # Weather one-liner (best-effort)
  # ---------------------------------------------------------------------------

  defp lookup_weather(nil, _game_dt), do: nil
  defp lookup_weather(_venue_id, nil), do: nil

  defp lookup_weather(venue_id, game_dt) when is_integer(venue_id) do
    game_dt_param = ensure_datetime(game_dt)

    sql = """
    SELECT temperature_2m, precipitation
      FROM mlb.game_weather_forecast
     WHERE venue_id = $1 AND game_datetime = $2
     LIMIT 1
    """

    case Repo.query(sql, [venue_id, game_dt_param]) do
      {:ok, %{rows: [[temp, precip] | _]}} -> format_weather(temp, precip)
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp format_weather(nil, nil), do: nil

  defp format_weather(temp, precip) do
    parts =
      [
        format_temp(temp),
        format_precip(precip)
      ]
      |> Enum.reject(&is_nil/1)

    case parts do
      [] -> nil
      list -> Enum.join(list, " · ")
    end
  end

  defp format_temp(nil), do: nil
  defp format_temp(t) when is_number(t), do: "#{round(t)}°F"
  defp format_temp(%Decimal{} = t), do: "#{round(Decimal.to_float(t))}°F"
  defp format_temp(_), do: nil

  defp format_precip(nil), do: nil

  defp format_precip(p) when is_number(p) do
    if p > 0, do: "rain #{Float.round(p * 1.0, 2)}\"", else: nil
  end

  defp format_precip(%Decimal{} = p) do
    f = Decimal.to_float(p)
    if f > 0, do: "rain #{Float.round(f, 2)}\"", else: nil
  end

  defp format_precip(_), do: nil

  defp ensure_datetime(%DateTime{} = dt), do: DateTime.truncate(dt, :second)
  defp ensure_datetime(%NaiveDateTime{} = ndt), do: NaiveDateTime.truncate(ndt, :second)
  defp ensure_datetime(other), do: other

  # ---------------------------------------------------------------------------
  # ET label
  # ---------------------------------------------------------------------------

  @doc """
  Formats a UTC `%DateTime{}` or `%NaiveDateTime{}` as a US Eastern wall-clock
  label, e.g. `"7:05 PM ET"`. Returns `nil` for `nil` input.

  Uses the same fixed-offset (UTC-4) assumption as the rest of the app — see
  `DateHelper` and X-AGENT-001.
  """
  @spec format_et_time(DateTime.t() | NaiveDateTime.t() | nil) :: String.t() | nil
  def format_et_time(nil), do: nil

  def format_et_time(%DateTime{} = dt) do
    dt
    |> DateTime.add(@eastern_offset_hours * 3600, :second)
    |> et_strftime()
  end

  def format_et_time(%NaiveDateTime{} = ndt) do
    case DateTime.from_naive(ndt, "Etc/UTC") do
      {:ok, dt} -> format_et_time(dt)
      _ -> nil
    end
  end

  def format_et_time(_), do: nil

  defp et_strftime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%-I:%M %p ET")
  end

  # ---------------------------------------------------------------------------
  # Cache (de)serialization
  # ---------------------------------------------------------------------------

  defp encode_card(card) when is_map(card) do
    card
    |> Map.update!(:opponent_team, &serialize_team/1)
    |> Map.update!(:game_datetime_utc, &serialize_datetime/1)
    |> Jason.encode!()
  end

  defp serialize_team(nil), do: nil

  defp serialize_team(%Team{} = team) do
    %{
      "id" => team.id,
      "name" => team.name,
      "slug" => team.slug,
      "abbreviation" => team.abbreviation
    }
  end

  defp serialize_datetime(nil), do: nil

  defp serialize_datetime(%DateTime{} = dt),
    do: %{"kind" => "datetime", "iso" => DateTime.to_iso8601(dt)}

  defp serialize_datetime(%NaiveDateTime{} = ndt),
    do: %{"kind" => "naive", "iso" => NaiveDateTime.to_iso8601(ndt)}

  defp decode_card(raw) when is_binary(raw) do
    case Jason.decode(raw) do
      {:ok, map} when is_map(map) ->
        try do
          {:ok, deserialize_card(map)}
        rescue
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp deserialize_card(map) do
    %{
      scheduled_game_id: map["scheduled_game_id"],
      is_home: map["is_home"],
      opponent_team: deserialize_team(map["opponent_team"]),
      opponent_name: map["opponent_name"],
      venue_name: map["venue_name"],
      venue_id: map["venue_id"],
      game_datetime_utc: deserialize_datetime(map["game_datetime_utc"]),
      local_time_label: map["local_time_label"],
      probable_pitcher_name: map["probable_pitcher_name"],
      pitcher_record_label: map["pitcher_record_label"],
      weather_oneliner: map["weather_oneliner"]
    }
  end

  defp deserialize_team(nil), do: nil

  defp deserialize_team(map) when is_map(map) do
    %Team{
      id: map["id"],
      name: map["name"],
      slug: map["slug"],
      abbreviation: map["abbreviation"]
    }
  end

  defp deserialize_datetime(nil), do: nil

  defp deserialize_datetime(%{"kind" => "datetime", "iso" => iso}) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp deserialize_datetime(%{"kind" => "naive", "iso" => iso}) do
    case NaiveDateTime.from_iso8601(iso) do
      {:ok, ndt} -> ndt
      _ -> nil
    end
  end

  defp deserialize_datetime(_), do: nil
end
