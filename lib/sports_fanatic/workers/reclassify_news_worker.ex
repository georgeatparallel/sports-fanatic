defmodule SportsFanatic.Workers.ReclassifyNewsWorker do
  @moduledoc """
  Re-classifies existing news items that have outdated category values.

  Targets articles with legacy body-part injury categories (e.g., injury_elbow)
  or generic "news" category that contain injury-related keywords.
  Sends them back through the Python bridge AI classifier to get the new
  severity/trajectory-based categories.

  Enqueue manually:
      %{} |> SportsFanatic.Workers.ReclassifyNewsWorker.new() |> Oban.insert()

  Or with a custom batch size:
      %{"batch_size" => 50} |> SportsFanatic.Workers.ReclassifyNewsWorker.new() |> Oban.insert()
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: 300]

  alias SportsFanatic.Content.NewsItem
  alias SportsFanatic.PythonBridge
  alias SportsFanatic.Repo

  import Ecto.Query

  require Logger

  @legacy_categories ~w(
    injury_elbow injury_shoulder injury_oblique injury_back
    injury_knee injury_hamstring injury_other hit_by_pitch
  )

  @default_batch_size 25

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    batch_size = Map.get(args, "batch_size", @default_batch_size)

    articles = fetch_reclassifiable_articles(batch_size)

    if Enum.empty?(articles) do
      Logger.info("ReclassifyNewsWorker: no articles to reclassify")
      :ok
    else
      {success, failed} = reclassify_batch(articles)
      Logger.info("ReclassifyNewsWorker: reclassified=#{success} failed=#{failed}")
      :ok
    end
  end

  defp fetch_reclassifiable_articles(batch_size) do
    # Fetch articles with legacy body-part categories
    legacy_query =
      NewsItem
      |> where([n], n.category in ^@legacy_categories)
      |> limit(^batch_size)
      |> Repo.all()

    remaining = batch_size - length(legacy_query)

    # If we have room, also fetch generic "news" articles with injury keywords
    keyword_query =
      if remaining > 0 do
        keyword_pattern = "%injury%"

        NewsItem
        |> where([n], n.category == "news")
        |> where(
          [n],
          ilike(n.title, ^keyword_pattern) or ilike(n.body, ^keyword_pattern)
        )
        |> limit(^remaining)
        |> Repo.all()
      else
        []
      end

    legacy_query ++ keyword_query
  end

  defp reclassify_batch(articles) do
    Enum.reduce(articles, {0, 0}, fn article, {success, failed} ->
      case reclassify_article(article) do
        :ok -> {success + 1, failed}
        :error -> {success, failed + 1}
      end
    end)
  end

  defp reclassify_article(article) do
    excerpt = String.slice(article.body || "", 0, 500)

    case PythonBridge.analyze_news(article.title, excerpt) do
      {:ok, %{"category" => new_category, "sentiment" => sentiment, "summary" => summary}} ->
        changeset =
          NewsItem.changeset(article, %{
            category: new_category,
            sentiment: sentiment,
            ai_summary: summary,
            ai_processed: true
          })

        case Repo.update(changeset) do
          {:ok, _} ->
            Logger.debug(
              "ReclassifyNewsWorker: #{article.id} #{article.category} -> #{new_category}"
            )

            :ok

          {:error, changeset} ->
            Logger.warning(
              "ReclassifyNewsWorker: failed to update #{article.id}: #{inspect(changeset.errors)}"
            )

            :error
        end

      {:error, reason} ->
        Logger.warning(
          "ReclassifyNewsWorker: AI analysis failed for #{article.id}: #{inspect(reason)}"
        )

        :error

      _ ->
        :error
    end
  end
end
