defmodule SportsFanatic.Predictions do
  @moduledoc """
  Context API for the hit-predictions pipeline.

  Read paths cache through Valkey under the
  `sf:data:hit_prediction:{mlb_id}:{YYYY-MM-DD}` namespace (TTL 5 minutes).
  Write paths are owned by `SportsFanatic.Workers.PredictHitsWorker`.
  """

  import Ecto.Query

  alias SportsFanatic.Cache
  alias SportsFanatic.Predictions.HitPrediction
  alias SportsFanatic.Repo
  alias SportsFanatic.Workers.DailyHitPredictionsWorker

  @doc "Today (Eastern) hit predictions sorted by probability desc."
  def list_today(opts \\ []), do: list_for_date(SportsFanatic.DateHelper.today(), opts)

  @doc """
  All hit predictions for `date`. Opts:

    * `:team` — filter by `player_team` (string)
    * `:limit` — max rows
    * `:min_prob` — minimum hit_prob
  """
  @spec list_for_date(Date.t(), keyword) :: [HitPrediction.t()]
  def list_for_date(%Date{} = date, opts \\ []) do
    HitPrediction
    |> where([h], h.prediction_date == ^date)
    |> maybe_team(opts[:team])
    |> maybe_min_prob(opts[:min_prob])
    |> order_by([h], desc: h.hit_prob)
    |> maybe_limit(opts[:limit])
    |> Repo.all()
  end

  @doc """
  Fetch a per-player prediction for `date` (today by default). Reads cache
  first; falls back to Postgres and warms the cache.
  """
  @spec get_for_player(integer, Date.t() | nil) :: HitPrediction.t() | nil
  def get_for_player(player_mlb_id, date \\ nil)

  def get_for_player(player_mlb_id, nil),
    do: get_for_player(player_mlb_id, SportsFanatic.DateHelper.today())

  def get_for_player(player_mlb_id, %Date{} = date) when is_integer(player_mlb_id) do
    key = cache_key(player_mlb_id, date)

    case Cache.get(key) do
      {:ok, nil} ->
        case load_from_db(player_mlb_id, date) do
          nil ->
            nil

          %HitPrediction{} = hp ->
            with {:ok, encoded} <- Jason.encode(serialize(hp)) do
              Cache.set(key, encoded, 300)
            end

            hp
        end

      {:ok, raw} when is_binary(raw) ->
        case Jason.decode(raw) do
          {:ok, map} -> deserialize(map)
          _ -> load_from_db(player_mlb_id, date)
        end

      _ ->
        load_from_db(player_mlb_id, date)
    end
  end

  def get_for_player(_, _), do: nil

  @doc """
  Last `limit` pipeline runs of type `hit_predict_daily` for the admin tab.
  """
  def list_runs(limit \\ 30) do
    sql = """
    SELECT id, status, started_at, completed_at, error, metadata
      FROM system.pipeline_runs
     WHERE pipeline_name = 'hit_predict_daily'
     ORDER BY started_at DESC
     LIMIT $1
    """

    Repo.query!(sql, [limit]).rows
    |> Enum.map(fn [id, status, started, completed, error, metadata] ->
      %{
        id: id,
        status: status,
        started_at: started,
        completed_at: completed,
        error: error,
        metadata: metadata || %{}
      }
    end)
  rescue
    _ -> []
  end

  @doc "Enqueue an immediate run. Pass `:today` or a `Date`."
  @spec run_now(Date.t() | :today) :: {:ok, Oban.Job.t()} | {:error, term}
  def run_now(:today), do: run_now(SportsFanatic.DateHelper.today())

  def run_now(%Date{} = date) do
    %{"date" => Date.to_iso8601(date), "force" => true}
    |> DailyHitPredictionsWorker.new()
    |> Oban.insert()
  end

  @doc "Stream of all predictions for `player_mlb_id`, newest first."
  def stream_player_results(player_mlb_id) when is_integer(player_mlb_id) do
    HitPrediction
    |> where([h], h.player_mlb_id == ^player_mlb_id)
    |> order_by([h], desc: h.prediction_date)
  end

  ## --- Helpers --------------------------------------------------------------

  defp load_from_db(player_mlb_id, date) do
    HitPrediction
    |> where([h], h.player_mlb_id == ^player_mlb_id and h.prediction_date == ^date)
    |> Repo.one()
  end

  defp cache_key(mlb_id, %Date{} = d),
    do: "sf:data:hit_prediction:#{mlb_id}:#{Date.to_iso8601(d)}"

  defp serialize(%HitPrediction{} = hp) do
    hp
    |> Map.from_struct()
    |> Map.drop([:__meta__])
  end

  defp deserialize(map) when is_map(map) do
    struct(HitPrediction, atomize_keys(map))
  end

  defp atomize_keys(m) do
    Enum.into(m, %{}, fn
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
      {k, v} -> {k, v}
    end)
  rescue
    _ -> %{}
  end

  defp maybe_team(q, nil), do: q
  defp maybe_team(q, team), do: where(q, [h], h.player_team == ^team)
  defp maybe_min_prob(q, nil), do: q
  defp maybe_min_prob(q, p), do: where(q, [h], h.hit_prob >= ^p)
  defp maybe_limit(q, nil), do: q
  defp maybe_limit(q, l) when is_integer(l), do: limit(q, ^l)
end
