defmodule SportsFanatic.Workers.ScheduledExaSearchWorker do
  @moduledoc """
  Daily Oban worker (10am ET / 14:00 UTC) that runs Exa searches for all
  scheduled query clusters and processes discovered articles through the
  classification pipeline.
  """

  use Oban.Worker, queue: :content_generation, max_attempts: 3

  alias SportsFanatic.Agents.Actions.{ClassifyArticle, SearchExa}
  alias SportsFanatic.ChatBot

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    clusters = ChatBot.list_scheduled_clusters()

    if clusters == [] do
      Logger.debug("ScheduledExaSearchWorker: no scheduled clusters")
      :ok
    else
      Logger.info("ScheduledExaSearchWorker: running #{length(clusters)} scheduled searches")

      Enum.each(clusters, fn cluster ->
        run_cluster_search(cluster)
      end)

      :ok
    end
  end

  defp run_cluster_search(cluster) do
    query = cluster.representative_query

    case SearchExa.run(%{query: "#{query} MLB baseball", num_results: 5, days_back: 1}, %{}) do
      {:ok, %{new_articles: new_articles}} when new_articles != [] ->
        Logger.info(
          "ScheduledExa: found #{length(new_articles)} new articles for cluster #{cluster.id}"
        )

        Enum.each(new_articles, fn article ->
          ClassifyArticle.run(
            %{
              title: article.title,
              body: article.text,
              source_url: article.url,
              author: article.author
            },
            %{}
          )
        end)

        # Update last_run_at
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        ChatBot.update_cluster(cluster, %{last_run_at: now})

      {:ok, _} ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        ChatBot.update_cluster(cluster, %{last_run_at: now})

      {:error, reason} ->
        Logger.warning("ScheduledExa search failed for cluster #{cluster.id}: #{inspect(reason)}")
    end
  rescue
    e ->
      Logger.error("ScheduledExa error for cluster #{cluster.id}: #{inspect(e)}")
  end
end
