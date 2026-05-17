defmodule SportsFanatic.Workers.PredictHitsWorker do
  @moduledoc """
  Assembles training rows + inference rows, calls
  `SportsFanatic.Predictions.Inference.score/2`, and upserts the resulting
  per-player predictions into `mlb.hit_predictions`.

  Internal parallelism: feature computation runs through
  `Task.async_stream` with concurrency from
  `:feature_compute_concurrency` (default 16).
  """

  use Oban.Worker,
    queue: :predictions,
    max_attempts: 3,
    unique: [period: 3600, fields: [:worker, :args]]

  alias Phoenix.PubSub
  alias SportsFanatic.Cache
  alias SportsFanatic.Predictions.{Features, HitPrediction, Inference}
  alias SportsFanatic.Repo

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    date = parse_date(args["date"]) || SportsFanatic.DateHelper.today()
    run_id = parse_run_id(args["pipeline_run_id"])
    run_for_date(date, run_id)
  end

  @doc """
  Returns `{:ok, count, model_version}` or `{:error, reason}`.
  """
  @spec run_for_date(Date.t(), binary | nil) ::
          {:ok, integer, String.t() | nil} | {:error, term}
  def run_for_date(%Date{} = date, run_id \\ nil) do
    concurrency =
      Application.get_env(:sports_fanatic, :predictions, [])[:feature_compute_concurrency] || 16

    train_end = Date.add(date, -1)
    train_start = Date.new!(max(2021, date.year - 3), 1, 1)

    Logger.info("PredictHitsWorker: training #{train_start} → #{train_end}, target=#{date}")
    training_rows = Features.build_training_rows(train_start, train_end)

    if length(training_rows) < 50 do
      Logger.warning(
        "PredictHitsWorker: insufficient training data (#{length(training_rows)}); skipping"
      )

      {:ok, 0, nil}
    else
      lineup_targets = lineup_targets(date)
      Logger.info("PredictHitsWorker: building features for #{length(lineup_targets)} players")

      inference_rows =
        lineup_targets
        |> Task.async_stream(&build_row(&1, date),
          max_concurrency: concurrency,
          timeout: 30_000,
          on_timeout: :kill_task
        )
        |> Enum.flat_map(fn
          {:ok, %{} = row} -> [row]
          _ -> []
        end)

      case Inference.score(training_rows, Enum.map(inference_rows, & &1.features)) do
        {:ok, predictions, version} ->
          merged = merge_predictions(inference_rows, predictions, version, date, run_id)
          inserted = upsert_chunks(merged)
          invalidate_cache(date)
          broadcast(date)
          Logger.info("PredictHitsWorker: wrote #{inserted} predictions for #{date}")
          {:ok, inserted, version}

        err ->
          Logger.error("PredictHitsWorker: inference failed (#{inspect(err)})")
          err
      end
    end
  end

  ## ------------------------------------------------------------------------

  defp lineup_targets(date) do
    sql = """
    SELECT (p.external_ids->>'mlb_id')::int    AS player_mlb_id,
           p.id                                AS player_id,
           p.full_name                         AS player_name,
           tt.name                             AS player_team,
           (tt.external_ids->>'mlb_id')::int   AS player_team_id,
           sg.venue_id                         AS venue_id,
           sg.venue_name                       AS venue_name,
           sg.game_id                          AS game_id,
           sg.game_datetime                    AS game_datetime,
           sg.home_mlb_id                      AS home_mlb_id,
           sg.away_mlb_id                      AS away_mlb_id,
           sg.home_name                        AS home_name,
           sg.away_name                        AS away_name,
           sg.home_probable_pitcher            AS home_pitcher_name,
           sg.away_probable_pitcher            AS away_pitcher_name,
           g.home_starter_mlb_id               AS home_starter_mlb_id,
           g.away_starter_mlb_id               AS away_starter_mlb_id,
           l.batting_order                     AS batting_order,
           l.position                          AS position
      FROM mlb.lineups l
      JOIN public.players p ON p.id = l.player_id
      JOIN public.teams tt ON tt.id = p.team_id
      JOIN mlb.scheduled_games sg ON sg.game_date = l.game_date
                                  AND ((tt.external_ids->>'mlb_id')::int IN (sg.home_mlb_id, sg.away_mlb_id))
      LEFT JOIN mlb.games g ON g.game_id = sg.game_id
     WHERE l.game_date = $1
       AND p.external_ids ? 'mlb_id'
    """

    Repo.query!(sql, [date]).rows |> Enum.map(&row_to_target/1)
  rescue
    e ->
      Logger.warning("PredictHitsWorker: lineup_targets failed (#{inspect(e)})")
      []
  end

  defp row_to_target([
         player_mlb_id,
         player_id,
         player_name,
         player_team,
         player_team_id,
         venue_id,
         venue_name,
         game_id,
         game_datetime,
         home_mlb_id,
         away_mlb_id,
         home_name,
         away_name,
         home_pitcher_name,
         away_pitcher_name,
         home_starter_mlb_id,
         away_starter_mlb_id,
         batting_order,
         position
       ]) do
    is_home = player_team_id == home_mlb_id

    {vs_team, vs_team_id, probable_pitcher_name, probable_pitcher_mlb_id} =
      if is_home,
        do: {away_name, away_mlb_id, away_pitcher_name, away_starter_mlb_id},
        else: {home_name, home_mlb_id, home_pitcher_name, home_starter_mlb_id}

    %{
      player_mlb_id: player_mlb_id,
      player_id: player_id,
      player_name: player_name,
      player_team: player_team,
      player_team_id: player_team_id,
      vs_team: vs_team,
      vs_team_id: vs_team_id,
      game_id: game_id,
      game_datetime: game_datetime,
      is_home: is_home,
      batting_order: batting_order,
      position: position,
      venue_id: venue_id,
      venue_name: venue_name,
      probable_pitcher_name: probable_pitcher_name,
      probable_pitcher_mlb_id: probable_pitcher_mlb_id
    }
  end

  defp build_row(target, date) do
    weather = fetch_weather(target.venue_id, target.game_datetime)

    features =
      Features.build_inference_row(target.player_mlb_id, date,
        venue_id: target.venue_id,
        pitcher_mlb_id: target.probable_pitcher_mlb_id,
        is_home: target.is_home,
        batting_order: target.batting_order,
        weather: weather
      )

    %{target: target, features: features, weather: weather}
  rescue
    e ->
      Logger.warning("PredictHitsWorker: feature row failed (#{inspect(e)})")
      nil
  end

  defp fetch_weather(nil, _), do: nil
  defp fetch_weather(_, nil), do: nil

  defp fetch_weather(venue_id, game_dt) do
    sql = """
    SELECT temperature_2m, wind_speed_10m, wind_direction_10m, precipitation, weathercode, surface_pressure
      FROM mlb.game_weather_forecast
     WHERE venue_id = $1 AND game_datetime = $2
     LIMIT 1
    """

    case Repo.query!(sql, [venue_id, game_dt]).rows do
      [[t, ws, wd, prec, wc, sp] | _] ->
        %{
          "temperature_2m" => t,
          "wind_speed_10m" => ws,
          "wind_direction_10m" => wd,
          "precipitation" => prec,
          "weathercode" => wc,
          "surface_pressure" => sp
        }

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp merge_predictions(rows, predictions, version, date, run_id) do
    pred_by_id =
      Enum.reduce(predictions, %{}, fn pred, acc ->
        case pred["player_mlb_id"] do
          nil -> acc
          id -> Map.put(acc, id, pred)
        end
      end)

    Enum.flat_map(rows, fn %{target: t, features: f, weather: w} ->
      case Map.get(pred_by_id, t.player_mlb_id) do
        nil ->
          []

        pred ->
          prob = pred["hit_prob"] || 0.0
          tier = HitPrediction.tier_for_prob(prob)

          [
            %{
              pipeline_run_id: run_id,
              prediction_date: date,
              player_id: t.player_id,
              player_mlb_id: t.player_mlb_id,
              player_name: t.player_name,
              player_team: t.player_team,
              player_team_id: t.player_team_id,
              vs_team: t.vs_team,
              vs_team_id: t.vs_team_id,
              game_id: t.game_id,
              game_datetime: t.game_datetime,
              is_home: t.is_home,
              batting_order: t.batting_order,
              probable_pitcher_name: t.probable_pitcher_name,
              probable_pitcher_mlb_id: t.probable_pitcher_mlb_id,
              venue_id: t.venue_id,
              venue_name: t.venue_name,
              hit_prob: prob,
              prediction: pred["prediction"] || if(prob >= 0.5, do: "Hit", else: "No Hit"),
              confidence_tier: tier,
              temperature: w && w["temperature_2m"],
              wind_speed: w && w["wind_speed_10m"],
              wind_direction: w && w["wind_direction_10m"],
              precipitation: w && w["precipitation"],
              weathercode: w && w["weathercode"],
              surface_pressure: w && w["surface_pressure"],
              bvp_avg: f["bvp_avg"],
              bvp_at_bats: f["bvp_at_bats"],
              features: f,
              model_version: version,
              inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
              updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
            }
          ]
      end
    end)
  end

  defp upsert_chunks(rows) when rows == [], do: 0

  defp upsert_chunks(rows) do
    rows
    |> Enum.chunk_every(500)
    |> Enum.reduce(0, fn chunk, acc ->
      {count, _} =
        Repo.insert_all(HitPrediction, chunk,
          on_conflict:
            {:replace_all_except,
             [:id, :inserted_at, :pipeline_run_id, :actual_result, :actual_hits]},
          conflict_target: [:prediction_date, :player_mlb_id]
        )

      acc + count
    end)
  end

  defp invalidate_cache(date) do
    iso = Date.to_iso8601(date)
    Cache.del_pattern("sf:data:hit_prediction:*:#{iso}")
    Cache.del_pattern("sf:data:predictions:*")
    Cache.del("sf:page:predictions:#{iso}")
    Cache.del_pattern("sf:page:player:*")
  rescue
    _ -> :ok
  end

  defp broadcast(date) do
    iso = Date.to_iso8601(date)
    PubSub.broadcast(SportsFanatic.PubSub, "predictions:hits:#{iso}", {:hits_ready, date})
  end

  defp parse_date(nil), do: nil
  defp parse_date(%Date{} = d), do: d

  defp parse_date(s) when is_binary(s) do
    case Date.from_iso8601(s) do
      {:ok, d} -> d
      _ -> nil
    end
  end

  defp parse_run_id(nil), do: nil
  defp parse_run_id(s) when is_binary(s), do: s
end
