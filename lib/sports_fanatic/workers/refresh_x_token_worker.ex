defmodule SportsFanatic.Workers.RefreshXTokenWorker do
  @moduledoc """
  Hourly Oban worker that refreshes the X OAuth access token when it has
  less than 5 minutes of life remaining. On failure, broadcasts
  `{:token_failure, reason}` on `"admin:x_agent"` so the admin tab can
  surface the error.

  Gated by the `x_agent_enabled` feature flag — returns `{:ok, :disabled}`
  when the flag is off.
  """

  use Oban.Worker, queue: :x_agent, max_attempts: 3, unique: [period: 3000]

  require Logger
  alias SportsFanatic.FeatureFlags
  alias SportsFanatic.X

  @impl true
  def perform(%Oban.Job{}) do
    if FeatureFlags.enabled?("x_agent_enabled") do
      do_perform()
    else
      {:ok, :disabled}
    end
  end

  defp do_perform do
    case X.refresh_if_needed() do
      {:ok, _creds} ->
        :ok

      {:error, :missing} ->
        # No credentials yet — not an error; admin needs to OAuth.
        {:ok, :no_credentials}

      {:error, reason} = err ->
        Logger.warning("RefreshXTokenWorker failed: #{inspect(reason)}")
        broadcast_failure(reason)
        err
    end
  end

  defp broadcast_failure(reason) do
    if Process.whereis(SportsFanatic.PubSub) do
      Phoenix.PubSub.broadcast(
        SportsFanatic.PubSub,
        "admin:x_agent",
        {:token_failure, reason}
      )
    end
  rescue
    _ -> :ok
  end
end
