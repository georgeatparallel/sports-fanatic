defmodule SportsFanatic.Workers.ConsolidateQueriesWorker do
  @moduledoc """
  Hourly Oban worker that clusters unclustered chat messages into
  query clusters based on entity overlap and keyword similarity.
  """

  use Oban.Worker, queue: :system, max_attempts: 3

  alias SportsFanatic.Agents.Actions.ResolveEntities
  alias SportsFanatic.ChatBot

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    messages = ChatBot.list_unclustered_messages(limit: 100)

    if messages == [] do
      Logger.debug("ConsolidateQueriesWorker: no unclustered messages")
      :ok
    else
      Logger.info("ConsolidateQueriesWorker: processing #{length(messages)} unclustered messages")
      clusters = ChatBot.list_clusters(limit: 200)

      Enum.each(messages, fn message ->
        process_message(message, clusters)
      end)

      :ok
    end
  rescue
    e ->
      Logger.error("ConsolidateQueriesWorker error: #{inspect(e)}")
      {:error, Exception.message(e)}
  end

  defp process_message(message, existing_clusters) do
    # Resolve entities from the message text
    {:ok, entities} = ResolveEntities.run(%{text: message.content}, %{})

    # Extract keywords from message
    keywords = extract_keywords(message.content)

    # Try to find a matching cluster
    matching_cluster =
      Enum.find(existing_clusters, fn cluster ->
        entity_overlap?(cluster, entities) || keyword_overlap?(cluster, keywords)
      end)

    case matching_cluster do
      nil ->
        # Create new cluster
        case ChatBot.create_cluster(%{
               representative_query: message.content,
               entity_player_ids: entities.player_ids,
               entity_team_ids: entities.team_ids,
               topics: keywords,
               query_count: 1
             }) do
          {:ok, cluster} ->
            ChatBot.assign_to_cluster(%{
              cluster_id: cluster.id,
              message_id: message.id,
              raw_query: message.content
            })

          {:error, reason} ->
            Logger.warning("Failed to create cluster: #{inspect(reason)}")
        end

      cluster ->
        # Update existing cluster
        ChatBot.update_cluster(cluster, %{
          query_count: cluster.query_count + 1,
          entity_player_ids: Enum.uniq(cluster.entity_player_ids ++ entities.player_ids),
          entity_team_ids: Enum.uniq(cluster.entity_team_ids ++ entities.team_ids),
          topics: Enum.uniq(cluster.topics ++ keywords) |> Enum.take(20)
        })

        ChatBot.assign_to_cluster(%{
          cluster_id: cluster.id,
          message_id: message.id,
          raw_query: message.content
        })
    end
  end

  defp entity_overlap?(cluster, entities) do
    player_overlap =
      MapSet.new(cluster.entity_player_ids)
      |> MapSet.intersection(MapSet.new(entities.player_ids))
      |> MapSet.size()

    team_overlap =
      MapSet.new(cluster.entity_team_ids)
      |> MapSet.intersection(MapSet.new(entities.team_ids))
      |> MapSet.size()

    player_overlap > 0 || team_overlap > 0
  end

  defp keyword_overlap?(cluster, keywords) do
    cluster_set = MapSet.new(cluster.topics)
    keyword_set = MapSet.new(keywords)

    overlap = MapSet.intersection(cluster_set, keyword_set) |> MapSet.size()
    total = max(MapSet.size(cluster_set), MapSet.size(keyword_set))

    total > 0 and overlap / total >= 0.7
  end

  @stop_words ~w(the a an is was are were be been being have has had do does did will would shall should may might can could and but or nor for yet so at by from in into of on to with about above after before between through during)

  defp extract_keywords(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s]/, " ")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reject(&(&1 in @stop_words))
    |> Enum.reject(&(String.length(&1) < 3))
    |> Enum.uniq()
    |> Enum.take(10)
  end
end
