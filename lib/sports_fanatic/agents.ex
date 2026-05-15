defmodule SportsFanatic.Agents do
  @moduledoc """
  Context for managing news agent settings and results.

  All operations are user-scoped: a user can only access their own
  settings and results. Rate limits are enforced at this layer.
  """

  import Ecto.Query

  alias SportsFanatic.Agents.NewsAgentResult
  alias SportsFanatic.Agents.NewsAgentSetting
  alias SportsFanatic.Repo

  require Logger

  @max_settings_per_user 20
  @max_settings_per_hour 5

  # ── Settings CRUD ──────────────────────────────────────────

  @doc """
  Creates a new agent setting for a user. Returns error if the user
  has reached the maximum number of active settings (#{@max_settings_per_user})
  or has exceeded the hourly rate limit (#{@max_settings_per_hour} per hour).
  """
  def create_setting(user_id, raw_prompt) when is_binary(user_id) and is_binary(raw_prompt) do
    hourly_count = count_user_settings_last_hour(user_id)

    cond do
      hourly_count >= @max_settings_per_hour ->
        {:error, :hourly_rate_limit_exceeded}

      count_user_settings(user_id) >= @max_settings_per_user ->
        {:error, :max_settings_reached}

      true ->
        %NewsAgentSetting{}
        |> NewsAgentSetting.create_changeset(%{user_id: user_id, raw_prompt: raw_prompt})
        |> Repo.insert()
    end
  end

  @doc "Lists all settings for a user, most recent first."
  def list_user_settings(user_id) do
    NewsAgentSetting
    |> where([s], s.user_id == ^user_id)
    |> order_by([s], desc: s.inserted_at)
    |> Repo.all()
  end

  @doc "Gets a single setting, scoped to the given user."
  def get_setting!(setting_id, user_id) do
    NewsAgentSetting
    |> where([s], s.id == ^setting_id and s.user_id == ^user_id)
    |> Repo.one!()
  end

  @doc "Gets a setting by ID without user scoping (for workers)."
  def get_setting(setting_id) do
    Repo.get(NewsAgentSetting, setting_id)
  end

  @doc "Updates a setting's parsed criteria, status, or execution results."
  def update_setting(%NewsAgentSetting{} = setting, attrs) do
    setting
    |> NewsAgentSetting.update_changeset(attrs)
    |> Repo.update()
  end

  @doc "Deletes a setting, scoped to the given user."
  def delete_setting(setting_id, user_id) do
    setting = get_setting!(setting_id, user_id)
    Repo.delete(setting)
  end

  @doc "Deletes all settings for a user."
  def clear_user_settings(user_id) do
    NewsAgentSetting
    |> where([s], s.user_id == ^user_id)
    |> Repo.delete_all()
  end

  @doc "Counts the number of settings for a user."
  def count_user_settings(user_id) do
    NewsAgentSetting
    |> where([s], s.user_id == ^user_id)
    |> Repo.aggregate(:count)
  end

  @doc "Counts settings created by a user in the last hour."
  def count_user_settings_last_hour(user_id) do
    NewsAgentSetting
    |> where([s], s.user_id == ^user_id and s.inserted_at > ago(1, "hour"))
    |> select([s], count(s.id))
    |> Repo.one()
  end

  # ── Results ────────────────────────────────────────────────

  @doc "Creates a new agent result."
  def create_result(attrs) do
    %NewsAgentResult{}
    |> NewsAgentResult.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Lists results for a user, optionally filtered by setting_id."
  def list_user_results(user_id, opts \\ []) do
    query =
      NewsAgentResult
      |> where([r], r.user_id == ^user_id)
      |> order_by([r], desc: r.created_at)

    query =
      case Keyword.get(opts, :setting_id) do
        nil -> query
        setting_id -> where(query, [r], r.setting_id == ^setting_id)
      end

    query =
      case Keyword.get(opts, :limit) do
        nil -> query
        limit -> limit(query, ^limit)
      end

    Repo.all(query)
  end

  @doc "Returns the most recent run's results for a user."
  def latest_results_for_user(user_id) do
    # Get the most recent run_date for this user
    latest_date =
      NewsAgentResult
      |> where([r], r.user_id == ^user_id)
      |> select([r], max(r.run_date))
      |> Repo.one()

    case latest_date do
      nil ->
        []

      date ->
        NewsAgentResult
        |> where([r], r.user_id == ^user_id and r.run_date == ^date)
        |> order_by([r], desc: r.created_at)
        |> preload(:setting)
        |> Repo.all()
    end
  end

  # ── Agent Execution Queries ────────────────────────────────

  @doc "Returns user IDs that have at least one active setting."
  def users_with_active_settings do
    NewsAgentSetting
    |> where([s], s.status == "active")
    |> select([s], s.user_id)
    |> distinct(true)
    |> Repo.all()
  end

  @doc "Returns active settings for a specific user."
  def active_settings_for_user(user_id) do
    NewsAgentSetting
    |> where([s], s.user_id == ^user_id and s.status == "active")
    |> Repo.all()
  end

  @doc "Lists all settings across all users (admin read-only view)."
  def list_all_settings(opts \\ []) do
    query =
      NewsAgentSetting
      |> order_by([s], desc: s.inserted_at)
      |> preload(:user)

    query =
      case Keyword.get(opts, :limit) do
        nil -> query
        limit -> limit(query, ^limit)
      end

    Repo.all(query)
  end
end
