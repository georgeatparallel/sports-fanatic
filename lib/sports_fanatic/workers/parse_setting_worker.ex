defmodule SportsFanatic.Workers.ParseSettingWorker do
  @moduledoc """
  Asynchronously parses a user's natural language agent setting
  via the Python Bridge LLM endpoint. Updates the setting with
  parsed criteria on success, or marks it as failed on error.

  Broadcasts updates via PubSub so the NewsLive UI can react.
  """

  use Oban.Worker,
    queue: :content_generation,
    max_attempts: 3

  alias SportsFanatic.Agents
  alias SportsFanatic.PythonBridge

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"setting_id" => setting_id}}) do
    case Agents.get_setting(setting_id) do
      nil ->
        Logger.warning("ParseSettingWorker: setting #{setting_id} not found")
        :ok

      setting ->
        parse_and_update(setting)
    end
  end

  defp parse_and_update(setting) do
    case PythonBridge.parse_setting(setting.raw_prompt) do
      {:ok, parsed} when is_map(parsed) ->
        case Agents.update_setting(setting, %{
               parsed_criteria: parsed,
               status: "active",
               error_message: nil
             }) do
          {:ok, updated} ->
            broadcast_update(updated)
            :ok

          {:error, changeset} ->
            Logger.error("ParseSettingWorker: failed to update setting: #{inspect(changeset)}")
            {:error, :update_failed}
        end

      {:error, :circuit_open} ->
        Logger.warning("ParseSettingWorker: circuit breaker open, will retry")
        {:error, :circuit_open}

      {:error, reason} ->
        Logger.error(
          "ParseSettingWorker: parse failed for setting #{setting.id}: #{inspect(reason)}"
        )

        Agents.update_setting(setting, %{
          status: "failed",
          error_message: "Unable to parse your setting. Please try again later."
        })

        broadcast_update(setting)
        :ok
    end
  end

  defp broadcast_update(setting) do
    Phoenix.PubSub.broadcast(
      SportsFanatic.PubSub,
      "agent:settings:#{setting.user_id}",
      {:setting_updated, setting}
    )
  end
end
