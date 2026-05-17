defmodule SportsFanatic.Agents.XContentAgent do
  @moduledoc """
  Synchronous composer for the daily X posts. Given a `post_type`, picks the
  matching action module and runs it. Returns the action's `{:ok, body}` map
  directly; the caller (`MainPostWorker`) handles persistence + posting.

  Not a GenServer — invoked inline from `MainPostWorker.perform/1`.
  """

  alias SportsFanatic.Agents.Actions

  @actions %{
    "top_hits" => Actions.GenerateTopHitsPost,
    "injury" => Actions.GenerateInjuryReportPost,
    "team_magazine" => Actions.GenerateTeamMagazinePost
  }

  @spec compose(post_type :: String.t()) :: {:ok, map()} | {:error, term()}
  def compose(post_type) when is_binary(post_type) do
    case Map.fetch(@actions, post_type) do
      {:ok, mod} -> mod.run(%{}, %{post_type: post_type})
      :error -> {:error, {:unknown_post_type, post_type}}
    end
  end

  @doc "Returns the action module map for inspection (testing)."
  def actions, do: @actions
end
