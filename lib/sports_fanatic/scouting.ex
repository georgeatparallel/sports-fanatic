defmodule SportsFanatic.Scouting do
  @moduledoc """
  Context module for the agentic scouting pipeline.

  Manages scouting runs, per-player logs, and source URL deduplication.
  """

  import Ecto.Query

  alias SportsFanatic.Content.PlayerSourceUrl
  alias SportsFanatic.Repo
  alias SportsFanatic.Scouting.{ScoutingRun, ScoutingRunLog}

  # --- Scouting Runs ---

  def create_run(attrs) do
    %ScoutingRun{}
    |> ScoutingRun.changeset(attrs)
    |> Repo.insert()
  end

  def update_run(%ScoutingRun{} = run, attrs) do
    run
    |> ScoutingRun.changeset(attrs)
    |> Repo.update()
  end

  def get_run!(id) do
    Repo.get!(ScoutingRun, id)
  end

  def get_run_with_logs(id) do
    ScoutingRun
    |> Repo.get!(id)
    |> Repo.preload(logs: from(l in ScoutingRunLog, order_by: [desc: l.inserted_at]))
  end

  def list_runs(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    ScoutingRun
    |> order_by([r], desc: r.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def increment_processed(%ScoutingRun{} = run) do
    {1, [updated]} =
      ScoutingRun
      |> where([r], r.id == ^run.id)
      |> select([r], r)
      |> Repo.update_all(inc: [processed_players: 1])

    updated
  end

  # --- Run Logs ---

  def create_log(attrs) do
    %ScoutingRunLog{}
    |> ScoutingRunLog.changeset(attrs)
    |> Repo.insert()
  end

  def list_logs_for_run(run_id) do
    ScoutingRunLog
    |> where([l], l.scouting_run_id == ^run_id)
    |> order_by([l], desc: l.inserted_at)
    |> Repo.all()
  end

  def list_logs_for_player_in_run(run_id, player_id) do
    ScoutingRunLog
    |> where([l], l.scouting_run_id == ^run_id and l.player_id == ^player_id)
    |> order_by([l], asc: l.inserted_at)
    |> Repo.all()
  end

  # --- Source URL Deduplication ---

  @doc "Returns the set of URLs already processed for a given player."
  def existing_urls_for_player(player_id) do
    PlayerSourceUrl
    |> where([u], u.player_id == ^player_id)
    |> select([u], u.url)
    |> Repo.all()
    |> MapSet.new()
  end

  def create_source_url(attrs) do
    %PlayerSourceUrl{}
    |> PlayerSourceUrl.changeset(attrs)
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:player_id, :url])
  end

  def update_source_url(%PlayerSourceUrl{} = source, attrs) do
    source
    |> PlayerSourceUrl.changeset(attrs)
    |> Repo.update()
  end

  @doc "Returns classified source URLs for a player, grouped by classification."
  def classified_sources_for_player(player_id) do
    PlayerSourceUrl
    |> where([u], u.player_id == ^player_id and not is_nil(u.classification))
    |> order_by([u], desc: u.processed_at)
    |> Repo.all()
    |> Enum.group_by(& &1.classification)
  end

  @doc "Returns the most recent source URLs for a player (limit configurable)."
  def recent_sources_for_player(player_id, limit \\ 20) do
    PlayerSourceUrl
    |> where([u], u.player_id == ^player_id and not is_nil(u.classification))
    |> order_by([u], desc: u.processed_at)
    |> limit(^limit)
    |> Repo.all()
  end
end
