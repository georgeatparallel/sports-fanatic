defmodule SportsFanatic.Players do
  @moduledoc """
  Context for the `/mlb/lineups/:date` Players page.

  Builds three grouped rosters, the slim search-roster JSON, and per-card
  render data (status badge, link target, headshot fallback flag).

  ## Three-group computation

  1. **In the lineup today** — players with a row in `mlb.lineups` for `date`
     that resolves to a `mlb.players` record (`Lineup.player_id` not nil).
     Sorted by `last_name` asc, `full_name` asc. Deduplicated by player id
     (`distinct: p.id`).
  2. **Active not in lineup** — players with `Player.status == "active"` who
     are not in the lineup group. Anti-join via `NOT IN ^lineup_ids`. Sorted
     by `last_name` asc, `full_name` asc.
  3. **Inactive** — players with `Player.status != "active"`. Sorted by
     `last_name` asc, `full_name` asc. Excludes players with a nil `slug`.

  `Player.status` defaults to `"active"` at row creation. Any value other than
  the literal string `"active"` is treated as inactive.

  ## Cache strategy

    * `sf:page:players:{YYYY-MM-DD}` — full rendered HTML, cached at the
      controller level via `Plug.Conn.register_before_send/2` for anonymous
      visitors only (see ADR-002 in `agent-notes/architect.md`). TTL:
      seconds until next Eastern midnight, floored at 600 s.
    * `sf:data:players:roster` — slim roster blob for the search dropdown,
      serialised with `:erlang.term_to_binary/2` (`:compressed`). TTL 24 h.
      Key builder: `Cache.players_roster_key/0`.
    * `sf:data:player:card:{mlb_id}` — per-card render data. `mlb_id` is the
      integer from `player.external_ids["mlb_id"]` when present; falls back
      to the player's binary UUID. Key builder: `Cache.player_card_key/1`.
      TTL 6 h.

  Cache invalidation hooks:
    - `FetchLineupsWorker` → deletes `sf:page:players:{date}` after a
      successful lineup fetch.
    - `GenerateScoutingWorker` / `GenerateScoutingOnDemandWorker` → deletes
      the per-card key per player; then deletes all `sf:page:players:*` keys
      once after the batch (debounced in `GenerateScoutingWorker`).
    - `X.InjuryReport.insert_and_cache/3` → same as scouting invalidation.
    - Roster key has no explicit invalidation hook; relies on the 24 h TTL
      (see `CACHE-PLR-1` in `docs/KNOWN_ISSUES.md`).

  ## Roster cap

  Realistically ≤ ~1500 active+inactive rows. If the inactive count exceeds
  ~2000 in production, add `where: p.updated_at >= ago(365, "day")` to the
  roster + inactive queries (out of scope for Phase 1 — see `CACHE-PLR-1`).

  ## Public API

    * `groups_for_date/1` — returns a `t:groups/0` map with three keys.
    * `groups_with_cards_for_date/1` — convenience wrapper that combines
      `groups_for_date/1` and `card_render_data/1` in one call.
    * `roster_for_search/0` — slim list of all players for the search dropdown.
    * `card_render_data/1` — batch-fetches per-card data for a list of player
      UUIDs; returns a `%{player_id => t:card_data/0}` map.
  """

  import Ecto.Query

  alias SportsFanatic.Cache
  alias SportsFanatic.Content.{InjuryReport, ScoutingReport}
  alias SportsFanatic.Mlb.{Lineup, Player}
  alias SportsFanatic.Players.InjuryBadge
  alias SportsFanatic.Repo

  require Logger

  @type group_row :: %{
          required(:player) => Player.t(),
          required(:team) => map() | nil,
          optional(:position) => String.t() | nil,
          optional(:batting_order) => integer() | nil
        }

  @type groups :: %{
          lineup: [group_row()],
          active_not_in_lineup: [group_row()],
          inactive: [group_row()]
        }

  @type card_data :: %{
          injury_badge: InjuryBadge.badge(),
          link_target: String.t(),
          has_scouting_report: boolean()
        }

  @doc """
  Returns the three groups for a given `%Date{}`. Each group is a list of
  `t:group_row/0` maps. Always returns all three keys — empty list when a
  group has no rows.

  Side effects: none (cache reads happen at the higher level via
  `groups_with_cards_for_date/1`).
  """
  @spec groups_for_date(Date.t()) :: groups()
  def groups_for_date(%Date{} = date) do
    lineup = lineup_group(date)
    lineup_player_ids = Enum.map(lineup, & &1.player.id)
    active = active_group(lineup_player_ids)
    inactive = inactive_group()

    %{lineup: lineup, active_not_in_lineup: active, inactive: inactive}
  end

  @doc """
  Returns a slim roster suitable for the client-side search dropdown.

  Each entry is a JSON-safe map:

      %{
        "mlb_id" => integer() | nil,
        "full_name" => String.t(),
        "last_name" => String.t() | nil,
        "team_slug" => String.t(),
        "team_abbr" => String.t() | nil,
        "slug" => String.t(),
        "href" => String.t()  # link target: scouting if available, else player page
      }

  Cached in Valkey at `Cache.players_roster_key/0` for up to 24 h. Cache
  misses repopulate from a single SELECT joining `mlb.players` →
  `mlb.teams` plus a single SELECT against `content.scouting_reports` to
  flag `has_scouting`.
  """
  @spec roster_for_search() :: [map()]
  def roster_for_search do
    key = Cache.players_roster_key()

    case Cache.get(key) do
      {:ok, blob} when is_binary(blob) ->
        decode_term(blob)

      _ ->
        roster = build_roster()
        _ = safe_set(key, encode_term(roster), 86_400)
        roster
    end
  rescue
    e ->
      Logger.warning("Players.roster_for_search cache error: #{inspect(e)}")
      build_roster()
  end

  @doc """
  Returns a map of player_uuid → `t:card_data/0` for the requested player
  ids. Per-card data is read from Valkey first; misses are batched into two
  SELECTs (scouting + injury), then re-cached.

  `player_ids` are the binary UUID primary keys from `mlb.players`.
  """
  @spec card_render_data([String.t()]) :: %{String.t() => card_data()}
  def card_render_data(player_ids) when is_list(player_ids) do
    player_ids
    |> Enum.uniq()
    |> Enum.reject(&is_nil/1)
    |> case do
      [] ->
        %{}

      ids ->
        scouting_map = latest_scouting_by_player(ids)
        injury_map = latest_injury_by_player(ids)
        team_slug_map = team_slug_by_player(ids)
        player_slug_map = player_slug_by_player(ids)

        for id <- ids, into: %{} do
          scouting_risk = Map.get(scouting_map, id)
          injury_status = Map.get(injury_map, id)
          team_slug = Map.get(team_slug_map, id)
          player_slug = Map.get(player_slug_map, id)
          has_scouting = Map.has_key?(scouting_map, id)
          badge = InjuryBadge.for_scouting_or_injury(scouting_risk, injury_status)
          link = link_target(team_slug, player_slug, has_scouting)
          {id, %{injury_badge: badge, link_target: link, has_scouting_report: has_scouting}}
        end
    end
  end

  @doc """
  Convenience wrapper: builds the three groups for `date` and the card-data
  map for every player across the groups in a single call. Useful for the
  controller.
  """
  @spec groups_with_cards_for_date(Date.t()) :: %{
          groups: groups(),
          cards: %{String.t() => card_data()}
        }
  def groups_with_cards_for_date(%Date{} = date) do
    groups = groups_for_date(date)

    ids =
      [groups.lineup, groups.active_not_in_lineup, groups.inactive]
      |> Enum.flat_map(&Enum.map(&1, fn r -> r.player.id end))

    %{groups: groups, cards: card_render_data(ids)}
  end

  # ── private queries ─────────────────────────────────────────

  defp lineup_group(date) do
    # Postgres `DISTINCT ON (p.id)` requires ORDER BY to start with the
    # DISTINCT ON expressions, so we sort by p.id at the DB level to make the
    # row pick deterministic (handles double-header / two-lineup edge cases)
    # and re-sort by last_name in Elixir for the user-facing alphabetical
    # ordering.
    from(l in Lineup,
      where: l.game_date == ^date and not is_nil(l.player_id),
      join: p in Player,
      on: p.id == l.player_id,
      left_join: t in assoc(p, :team),
      where: not is_nil(p.slug),
      distinct: p.id,
      order_by: [asc: p.id],
      select: %{
        player: p,
        team: t,
        position: l.position,
        batting_order: l.batting_order
      }
    )
    |> Repo.all()
    |> Enum.sort_by(fn row ->
      {row.player.last_name || "", row.player.full_name || "", row.player.id}
    end)
  end

  defp active_group([]), do: do_active_group([])
  defp active_group(lineup_ids), do: do_active_group(lineup_ids)

  defp do_active_group(lineup_ids) do
    base =
      from(p in Player,
        join: t in assoc(p, :team),
        where: p.status == "active",
        where: not is_nil(p.slug),
        order_by: [asc: p.last_name, asc: p.full_name],
        select: %{player: p, team: t}
      )

    query =
      if lineup_ids == [] do
        base
      else
        from([p, _t] in base, where: p.id not in ^lineup_ids)
      end

    Repo.all(query)
  end

  defp inactive_group do
    Repo.all(
      from(p in Player,
        join: t in assoc(p, :team),
        where: p.status != "active",
        where: not is_nil(p.slug),
        order_by: [asc: p.last_name, asc: p.full_name],
        select: %{player: p, team: t}
      )
    )
  end

  defp latest_scouting_by_player(player_ids) do
    Repo.all(
      from(sr in ScoutingReport,
        where: sr.player_id in ^player_ids,
        distinct: sr.player_id,
        order_by: [asc: sr.player_id, desc: sr.report_date],
        select: {sr.player_id, sr.injury_risk}
      )
    )
    |> Map.new()
  end

  defp latest_injury_by_player(player_ids) do
    Repo.all(
      from(ir in InjuryReport,
        where: ir.player_id in ^player_ids,
        distinct: ir.player_id,
        order_by: [asc: ir.player_id, desc: ir.run_date],
        select: {ir.player_id, ir.current_status}
      )
    )
    |> Map.new()
  end

  defp team_slug_by_player(player_ids) do
    Repo.all(
      from(p in Player,
        join: t in assoc(p, :team),
        where: p.id in ^player_ids,
        select: {p.id, t.slug}
      )
    )
    |> Map.new()
  end

  defp player_slug_by_player(player_ids) do
    Repo.all(
      from(p in Player,
        where: p.id in ^player_ids,
        select: {p.id, p.slug}
      )
    )
    |> Map.new()
  end

  defp build_roster do
    has_scouting_set =
      Repo.all(
        from(sr in ScoutingReport,
          distinct: sr.player_id,
          select: sr.player_id
        )
      )
      |> MapSet.new()

    Repo.all(
      from(p in Player,
        join: t in assoc(p, :team),
        where: not is_nil(p.slug) and not is_nil(t.slug),
        order_by: [asc: p.last_name, asc: p.full_name],
        select: %{
          id: p.id,
          full_name: p.full_name,
          last_name: p.last_name,
          slug: p.slug,
          team_slug: t.slug,
          team_abbr: t.abbreviation,
          external_ids: p.external_ids
        }
      )
    )
    |> Enum.map(fn row ->
      has_scouting = MapSet.member?(has_scouting_set, row.id)
      mlb_id = extract_mlb_id(row.external_ids)
      href = link_target(row.team_slug, row.slug, has_scouting)

      %{
        "mlb_id" => mlb_id,
        "full_name" => row.full_name,
        "last_name" => row.last_name,
        "team_slug" => row.team_slug,
        "team_abbr" => row.team_abbr,
        "slug" => row.slug,
        "href" => href,
        "has_scouting" => has_scouting
      }
    end)
  end

  defp link_target(nil, _, _), do: "/mlb/players"
  defp link_target(_, nil, _), do: "/mlb/players"

  defp link_target(team_slug, player_slug, true),
    do: "/mlb/scouting/#{team_slug}/#{player_slug}"

  defp link_target(team_slug, player_slug, _),
    do: "/mlb/players/#{team_slug}/#{player_slug}"

  defp extract_mlb_id(%{} = ext) do
    case Map.get(ext, "mlb_id") || Map.get(ext, :mlb_id) do
      v when is_integer(v) -> v
      v when is_binary(v) -> v
      _ -> nil
    end
  end

  defp extract_mlb_id(_), do: nil

  defp encode_term(term), do: :erlang.term_to_binary(term, [:compressed])

  defp decode_term(blob) when is_binary(blob), do: :erlang.binary_to_term(blob, [:safe])

  defp safe_set(key, value, ttl) do
    Cache.set(key, value, ttl)
  rescue
    _ -> :ok
  end
end
