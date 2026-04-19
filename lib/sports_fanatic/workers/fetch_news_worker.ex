defmodule SportsFanatic.Workers.FetchNewsWorker do
  @moduledoc "Fetches player news from FantasyNerds every 2 hours."

  use Oban.Worker,
    queue: :data_fetch,
    max_attempts: 3,
    unique: [period: 3600]

  alias SportsFanatic.Repo
  alias SportsFanatic.Content.NewsItem
  alias SportsFanatic.ExternalApis.FantasyNerds

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case FantasyNerds.fetch_news() do
      {:ok, news_list} when is_list(news_list) ->
        count =
          Enum.reduce(news_list, 0, fn item, acc ->
            slug = generate_news_slug(item["title"])

            changeset =
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

            case Repo.insert(changeset,
                   on_conflict: :nothing,
                   conflict_target: [:source, :external_id]
                 ) do
              {:ok, _} -> acc + 1
              _ -> acc
            end
          end)

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
