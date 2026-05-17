defmodule SportsFanatic.ChatBot do
  @moduledoc """
  Context for managing chat sessions, messages, rate limiting, and query clusters.

  All user-facing operations are scoped by user_id. Admin operations use
  separate functions that do not filter by user.
  """

  import Ecto.Query

  alias SportsFanatic.ChatBot.{ChatMessage, ChatSession, QueryCluster, QueryClusterMember}
  alias SportsFanatic.Repo

  @session_timeout_minutes 30
  @max_queries_per_hour 10
  @max_queries_per_day 50
  @max_context_messages 10

  # ── Sessions ──────────────────────────────────────────────────

  @doc """
  Finds an active session for the user with activity within the last
  #{@session_timeout_minutes} minutes, or creates a new one.
  """
  def get_or_create_session(user_id) when is_binary(user_id) do
    cutoff = DateTime.add(DateTime.utc_now(), -@session_timeout_minutes * 60, :second)

    query =
      from s in ChatSession,
        where: s.user_id == ^user_id and s.status == "active" and s.last_activity_at >= ^cutoff,
        order_by: [desc: s.last_activity_at],
        limit: 1

    case Repo.one(query) do
      nil ->
        create_session(user_id)

      session ->
        {:ok, session}
    end
  end

  defp create_session(user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %ChatSession{}
    |> ChatSession.changeset(%{
      user_id: user_id,
      status: "active",
      last_activity_at: now
    })
    |> Repo.insert()
  end

  @doc """
  Marks a session as expired.
  """
  def clear_session(session_id, user_id) when is_binary(session_id) and is_binary(user_id) do
    from(s in ChatSession, where: s.id == ^session_id and s.user_id == ^user_id)
    |> Repo.update_all(set: [status: "expired"])
  end

  @doc """
  Touches the session's last_activity_at timestamp.
  """
  def touch_session(session_id) when is_binary(session_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(s in ChatSession, where: s.id == ^session_id)
    |> Repo.update_all(set: [last_activity_at: now])
  end

  # ── Messages ──────────────────────────────────────────────────

  @doc """
  Creates a chat message in the given session.
  """
  def create_message(attrs) when is_map(attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    attrs = Map.put_new(attrs, :inserted_at, now)

    %ChatMessage{}
    |> ChatMessage.changeset(Map.new(attrs))
    |> Repo.insert()
  end

  @doc """
  Lists messages for a session, ordered by insertion time.
  """
  def list_session_messages(session_id) when is_binary(session_id) do
    from(m in ChatMessage,
      where: m.session_id == ^session_id,
      order_by: [asc: m.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Returns the last N messages for a session, suitable for LLM context.
  Only returns user and assistant messages (not progress).
  """
  def recent_context(session_id, limit \\ @max_context_messages)
      when is_binary(session_id) do
    from(m in ChatMessage,
      where: m.session_id == ^session_id and m.role in ["user", "assistant"],
      order_by: [desc: m.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
    |> Enum.reverse()
  end

  # ── Rate Limiting ─────────────────────────────────────────────

  @doc """
  Counts user chat queries in the last hour.
  """
  def count_user_queries_hour(user_id) when is_binary(user_id) do
    one_hour_ago = DateTime.add(DateTime.utc_now(), -3600, :second)

    from(m in ChatMessage,
      join: s in ChatSession,
      on: m.session_id == s.id,
      where: s.user_id == ^user_id and m.role == "user" and m.inserted_at >= ^one_hour_ago
    )
    |> Repo.aggregate(:count)
  end

  @doc """
  Counts user chat queries in the last 24 hours.
  """
  def count_user_queries_day(user_id) when is_binary(user_id) do
    one_day_ago = DateTime.add(DateTime.utc_now(), -86_400, :second)

    from(m in ChatMessage,
      join: s in ChatSession,
      on: m.session_id == s.id,
      where: s.user_id == ^user_id and m.role == "user" and m.inserted_at >= ^one_day_ago
    )
    |> Repo.aggregate(:count)
  end

  @doc """
  Checks rate limits for a user. Returns :ok or {:error, reason}.
  """
  def check_rate_limit(user_id) when is_binary(user_id) do
    cond do
      count_user_queries_hour(user_id) >= @max_queries_per_hour ->
        {:error, :hourly_limit_exceeded}

      count_user_queries_day(user_id) >= @max_queries_per_day ->
        {:error, :daily_limit_exceeded}

      true ->
        :ok
    end
  end

  # ── Admin ─────────────────────────────────────────────────────

  @doc """
  Lists all chat sessions with user preloaded (admin only). Supports
  pagination via limit/offset.
  """
  def list_all_sessions(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)

    from(s in ChatSession,
      join: u in assoc(s, :user),
      preload: [user: u],
      order_by: [desc: s.last_activity_at],
      limit: ^limit,
      offset: ^offset
    )
    |> Repo.all()
  end

  @doc """
  Counts messages for a given session.
  """
  def count_session_messages(session_id) when is_binary(session_id) do
    from(m in ChatMessage, where: m.session_id == ^session_id)
    |> Repo.aggregate(:count)
  end

  # ── Query Clusters ────────────────────────────────────────────

  @doc """
  Lists all query clusters, ordered by query_count descending.
  """
  def list_clusters(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(c in QueryCluster,
      order_by: [desc: c.query_count],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Lists only scheduled clusters.
  """
  def list_scheduled_clusters do
    from(c in QueryCluster,
      where: c.scheduled == true and c.schedule_frequency != "disabled"
    )
    |> Repo.all()
  end

  @doc """
  Creates a new query cluster.
  """
  def create_cluster(attrs) do
    %QueryCluster{}
    |> QueryCluster.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a query cluster.
  """
  def update_cluster(%QueryCluster{} = cluster, attrs) do
    cluster
    |> QueryCluster.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Gets a cluster by ID.
  """
  def get_cluster(id) when is_binary(id) do
    Repo.get(QueryCluster, id)
  end

  @doc """
  Assigns a chat message to a cluster.
  """
  def assign_to_cluster(attrs) do
    %QueryClusterMember{}
    |> QueryClusterMember.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists unclustered user messages (messages not in any cluster).
  """
  def list_unclustered_messages(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    from(m in ChatMessage,
      left_join: cm in QueryClusterMember,
      on: cm.message_id == m.id,
      where: m.role == "user" and is_nil(cm.id),
      order_by: [asc: m.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end
end
