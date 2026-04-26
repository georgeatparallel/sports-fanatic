defmodule SportsFanatic.Workers.FetchNewsWorker do
  @moduledoc "Fetches player news from FantasyNerds every 2 hours."

  use Oban.Worker,
    queue: :data_fetch,
    max_attempts: 3,
    unique: [period: 3600]

  alias SportsFanatic.Content.NewsItem
  alias SportsFanatic.ExternalApis.FantasyNerds
  alias SportsFanatic.Repo

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case FantasyNerds.fetch_news() do
      {:ok, news_list} when is_list(news_list) ->
        count = insert_news_items(news_list)
        Logger.info("Fetched #{count} new news items")
        :ok

      {:ok, _} ->
        Logger.info("No news items returned")
        :ok

      {:error, reason} ->
        Logger.error("Failed to fetch news: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp insert_news_items(news_list) do
    Enum.reduce(news_list, 0, fn item, acc ->
      case insert_news_item(item) do
        {:ok, _} -> acc + 1
        _ -> acc
      end
    end)
  end

  defp insert_news_item(item) do
    slug = generate_news_slug(item["title"])

    %NewsItem{}
    |> NewsItem.changeset(%{
      source: "fantasynerds",
      external_id: to_string(item["id"] || item["newsId"]),
      slug: slug,
      title: item["title"],
      body: item["body"] || item["analysis"] || "",
      summary: item["summary"],
      published_date: Date.utc_today(),
      category: item["category"] || "general"
    })
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:source, :external_id]
    )
  end

  defp generate_news_slug(nil), do: "untitled-#{System.unique_integer([:positive])}"

  defp generate_news_slug(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
    |> String.slice(0, 200)
  end
end
