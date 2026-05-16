defmodule SportsFanatic.Agents.AgentSupervisor do
  @moduledoc """
  Manages agent processes. Each user can have at most one active agent
  running. New queries cancel the previous agent for that user.

  Uses a Registry for user_id -> pid lookup and a DynamicSupervisor
  for process lifecycle management.
  """

  require Logger

  @registry SportsFanatic.AgentRegistry
  @supervisor SportsFanatic.AgentDynamicSupervisor

  @doc """
  Starts an agent for the given user. If an agent is already running
  for this user, it is cancelled first.

  The agent runs asynchronously and broadcasts results via PubSub.
  """
  def start_agent(user_id, query, opts \\ []) do
    # Cancel any existing agent for this user
    cancel_agent(user_id)

    child_spec = %{
      id: {__MODULE__, user_id},
      start: {Task, :start_link, [fn -> run_agent(user_id, query, opts) end]},
      restart: :temporary
    }

    case DynamicSupervisor.start_child(@supervisor, child_spec) do
      {:ok, pid} ->
        Registry.register(@registry, user_id, pid)
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start agent for user #{user_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Cancels the running agent for a user.
  """
  def cancel_agent(user_id) do
    case Registry.lookup(@registry, user_id) do
      [{pid, _}] ->
        # Unregister first, then terminate
        Registry.unregister(@registry, user_id)
        DynamicSupervisor.terminate_child(@supervisor, pid)
        :ok

      [] ->
        :ok
    end
  end

  @doc """
  Returns true if an agent is currently running for the user.
  """
  def agent_running?(user_id) do
    case Registry.lookup(@registry, user_id) do
      [{pid, _}] -> Process.alive?(pid)
      [] -> false
    end
  end

  defp run_agent(user_id, query, opts) do
    result =
      SportsFanatic.Agents.NewsAgent.run(
        query,
        Keyword.merge(opts, user_id: user_id)
      )

    case result do
      {:ok, %{summary: summary, news_item_ids: ids}} ->
        Phoenix.PubSub.broadcast(
          SportsFanatic.PubSub,
          "chat:#{user_id}",
          {:agent_complete, %{summary: summary, news_item_ids: ids}}
        )

      {:error, reason} ->
        error_msg =
          case reason do
            :timeout ->
              "The search took too long. Please try a simpler query."

            {:agent_error, msg} ->
              require Logger
              Logger.error("Agent error for user #{user_id}: #{inspect(msg)}")
              "Something went wrong, please try again."

            _ ->
              "Something went wrong, please try again."
          end

        Phoenix.PubSub.broadcast(
          SportsFanatic.PubSub,
          "chat:#{user_id}",
          {:agent_error, %{error: error_msg}}
        )
    end

    # Unregister on completion
    Registry.unregister(@registry, user_id)
  rescue
    e ->
      Logger.error("Agent crash for user #{user_id}: #{Exception.message(e)}")

      Phoenix.PubSub.broadcast(
        SportsFanatic.PubSub,
        "chat:#{user_id}",
        {:agent_error, %{error: "Something went wrong, please try again."}}
      )

      Registry.unregister(@registry, user_id)
  end
end
