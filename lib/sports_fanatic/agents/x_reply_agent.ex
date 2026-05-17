defmodule SportsFanatic.Agents.XReplyAgent do
  @moduledoc """
  Composes a single reply tweet given a target tweet + our local
  facts.

  Two-step ReAct-style loop:

    1. Extract candidate player names from the target tweet text via a
       cheap heuristic (look for capitalized 2-word sequences). For each,
       call `FetchPlayerStats` / `FetchInjuryStatus` to assemble facts.
    2. Call the Python Bridge `/x-agent/draft-reply` with the target tweet
       + assembled facts; the Bridge rejects prompt-injection patterns
       structurally.

  This is **not** a GenServer — invoked synchronously from
  `EngagementWatcherWorker` and `OutboundReplyWorker`.
  """

  require Logger

  alias SportsFanatic.Agents.Actions.{FetchInjuryStatus, FetchPlayerStats, FetchRecentPicks}
  alias SportsFanatic.PythonBridge

  @max_player_lookups 2

  @spec draft_for(target_tweet :: map(), our_context :: map()) ::
          {:ok, %{reply_body: String.t(), confidence: float()}} | {:error, term()}
  def draft_for(target_tweet, our_context \\ %{}) when is_map(target_tweet) do
    text = Map.get(target_tweet, "text") || Map.get(target_tweet, :text) || ""

    player_facts =
      text
      |> extract_player_candidates()
      |> Enum.take(@max_player_lookups)
      |> Enum.map(&assemble_player_facts/1)
      |> Enum.reject(&is_nil/1)

    recent =
      case FetchRecentPicks.run(%{}, %{}) do
        {:ok, %{picks: picks}} -> Enum.take(picks, 5)
        _ -> []
      end

    enriched_context =
      our_context
      |> Map.put(:player_facts, player_facts)
      |> Map.put(:recent_picks, recent)
      |> Map.put_new(:tone_directive, "warm 1-on-1 reply to a fan question")

    case PythonBridge.draft_x_reply(target_tweet, enriched_context) do
      {:ok, %{} = body} ->
        {:ok,
         %{
           reply_body: Map.get(body, "reply_body", ""),
           confidence: Map.get(body, "confidence", 0.5) |> normalize_confidence()
         }}

      {:error, reason} = err ->
        Logger.warning("XReplyAgent draft_for failed: #{inspect(reason)}")
        err
    end
  end

  defp extract_player_candidates(text) when is_binary(text) do
    Regex.scan(~r/\b[A-Z][a-z]+\s+[A-Z][a-z]+\b/u, text)
    |> List.flatten()
    |> Enum.uniq()
  end

  defp extract_player_candidates(_), do: []

  defp assemble_player_facts(name) do
    case FetchPlayerStats.run(%{"player_name" => name}, %{}) do
      {:ok, %{found: true} = stats} ->
        injury =
          case FetchInjuryStatus.run(%{"player_name" => name}, %{}) do
            {:ok, m} -> m
            _ -> %{}
          end

        Map.merge(stats, injury)

      _ ->
        nil
    end
  end

  defp normalize_confidence(n) when is_float(n), do: n
  defp normalize_confidence(n) when is_integer(n), do: n * 1.0
  defp normalize_confidence(_), do: 0.5
end
