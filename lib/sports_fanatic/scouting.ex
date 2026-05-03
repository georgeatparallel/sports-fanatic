defmodule SportsFanatic.Scouting do
  @moduledoc """
  Context module for the agentic scouting pipeline.

  Manages scouting runs, per-player logs, and source URL deduplication.
  """

  import Ecto.Query

  alias SportsFanatic.Content.PlayerSourceUrl
  alias SportsFanatic.Mlb.{Lineup, Player}
  alias SportsFanatic.Repo
  alias SportsFanatic.Scouting.{ScoutingRun, ScoutingRunLog}

  # --- Today's Lineup Players ---

  @doc """
  Returns players who appear in today's lineups, with their team preloaded.

  Joins mlb.lineups for today's date with public.players via the player_id FK.
  Falls back to matching via player_nerds_id -> external_ids->>'nerds_id' when
  player_id is nil. Only returns players with a slug and whose team has a slug.

  Returns an empty list if no lineups exist for today.
  """
  def players_in_todays_lineups do
    players_in_lineups_for_date(Date.utc_today())
  end

  @doc """
  Returns players who appear in lineups for the given date, with their team preloaded.
  """
  def players_in_lineups_for_date(date) do
    # Players linked via player_id FK
    fk_query =
      from(l in Lineup,
        where: l.game_date == ^date and not is_nil(l.player_id),
        join: p in Player,
        on: p.id == l.player_id,
        join: t in assoc(p, :team),
        where: not is_nil(p.slug) and not is_nil(t.slug),
        select: p.id
      )

    # Players linked via nerds_id (fallback when player_id is nil)
    nerds_query =
      from(l in Lineup,
        where: l.game_date == ^date and is_nil(l.player_id) and not is_nil(l.player_nerds_id),
        join: p in Player,
        on: fragment("(? ->> 'nerds_id')::int = ?", p.external_ids, l.player_nerds_id),
        join: t in assoc(p, :team),
        where: not is_nil(p.slug) and not is_nil(t.slug),
        select: p.id
      )

    fk_ids = Repo.all(fk_query)
    nerds_ids = Repo.all(nerds_query)
    all_ids = Enum.uniq(fk_ids ++ nerds_ids)

    if all_ids == [] do
      []
    else
      Player
      |> where([p], p.id in ^all_ids)
      |> preload(:team)
      |> Repo.all()
    end
  end

  @doc """
  Returns the count of players in today's lineups (without loading full records).
  """
  def todays_lineup_player_count do
    lineup_player_count_for_date(Date.utc_today())
  end

  @doc """
  Returns the count of distinct players in lineups for the given date.
  """
  def lineup_player_count_for_date(date) do
    fk_count_query =
      from(l in Lineup,
        where: l.game_date == ^date and not is_nil(l.player_id),
        join: p in Player,
        on: p.id == l.player_id,
        join: t in assoc(p, :team),
        where: not is_nil(p.slug) and not is_nil(t.slug),
        select: p.id
      )

    nerds_count_query =
      from(l in Lineup,
        where: l.game_date == ^date and is_nil(l.player_id) and not is_nil(l.player_nerds_id),
        join: p in Player,
        on: fragment("(? ->> 'nerds_id')::int = ?", p.external_ids, l.player_nerds_id),
        join: t in assoc(p, :team),
        where: not is_nil(p.slug) and not is_nil(t.slug),
        select: p.id
      )

    fk_ids = Repo.all(fk_count_query)
    nerds_ids = Repo.all(nerds_count_query)
    length(Enum.uniq(fk_ids ++ nerds_ids))
  end

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

  @doc "Returns source URLs for a player filtered by a single classification."
  def sources_for_player_by_category(player_id, category) do
    PlayerSourceUrl
    |> where([u], u.player_id == ^player_id and u.classification == ^category)
    |> order_by([u], desc: u.processed_at)
    |> Repo.all()
  end

  @doc "Returns a list of distinct classification strings that have sources for a player."
  def categories_for_player(player_id) do
    PlayerSourceUrl
    |> where([u], u.player_id == ^player_id and not is_nil(u.classification))
    |> select([u], u.classification)
    |> distinct(true)
    |> Repo.all()
  end
end
