defmodule SportsFanatic.Workers.FetchNewsWorker do
  @moduledoc """
  Fetches player news from FantasyNerds, enriches with AI analysis
  (category, sentiment, summary), stores raw payloads in S3, matches
  players/teams, and inserts enriched records into PostgreSQL.

  Runs every minute via Oban cron. Deduplicates by external_id.
  Gracefully degrades: S3 or AI failures do not block article storage.
  """

  use Oban.Worker,
    queue: :data_fetch,
    max_attempts: 3,
    unique: [period: 55]

  alias SportsFanatic.ExternalApis.FantasyNerds
  alias SportsFanatic.Mlb.{Player, Team}
  alias SportsFanatic.News
  alias SportsFanatic.News.EntityMatcher
  alias SportsFanatic.PythonBridge
  alias SportsFanatic.Repo
  alias SportsFanatic.Storage

  import Ecto.Query

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case FantasyNerds.fetch_news() do
      {:ok, news_list} when is_list(news_list) ->
        process_news(news_list)

      {:ok, _} ->
        Logger.info("FetchNewsWorker: no news items returned")
        :ok

      {:error, reason} ->
        Logger.error("FetchNewsWorker: failed to fetch news: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp process_news(news_list) do
    today = Date.utc_today()

    # Extract all external_ids in one pass
    articles_with_ids =
      Enum.map(news_list, fn item -> {item, extract_external_id(item)} end)

    all_external_ids = Enum.map(articles_with_ids, fn {_item, id} -> id end)

    # Single batch query: load all known external_ids for this source
    known_ids = News.existing_external_ids("fantasynerds", all_external_ids)

    # Filter to only truly new articles
    new_articles =
      Enum.filter(articles_with_ids, fn {_item, id} ->
        not MapSet.member?(known_ids, id)
      end)

    skipped = length(news_list) - length(new_articles)

    # Only load players and teams when there are new articles to process
    {inserted, _} = process_new_articles(new_articles)

    if inserted > 0 do
      News.invalidate_feed_cache(today)
    end

    Logger.info("FetchNewsWorker: inserted=#{inserted} skipped=#{skipped}")
    :ok
  end

  defp process_new_articles([]), do: {0, 0}

  defp process_new_articles(new_articles) do
    all_players = Player |> preload(:team) |> Repo.all()
    all_teams = Repo.all(Team)

    Enum.reduce(new_articles, {0, 0}, fn {item, external_id}, {ins, fail} ->
      case process_article(item, external_id, all_players, all_teams) do
        {:ok, _} -> {ins + 1, fail}
        {:error, _} -> {ins, fail + 1}
      end
    end)
  end

  defp process_article(item, external_id, all_players, all_teams) do
    title = item["article_headline"] || item["title"] || ""
    body = item["article_excerpt"] || item["body"] || item["analysis"] || ""
    author = item["article_author"] || item["author"]
    source_url = item["article_link"] || item["url"] || item["source_url"]
    published_date = parse_article_date(item["article_date"]) || Date.utc_today()
    slug = generate_news_slug(title)

    # Step 1: Upload raw JSON to S3 (non-blocking on failure)
    s3_key =
      case Storage.put_news_article(external_id, item) do
        {:ok, key} -> key
        {:error, _} -> nil
      end

    # Step 2: AI enrichment (non-blocking on failure)
    {category, sentiment, ai_summary} = analyze_with_ai(title, body)

    # Step 3: Entity matching
    # Extract player/team names from the article text
    matched_players = match_entities_from_text(title <> " " <> body, all_players, all_teams)
    {player_ids, team_ids} = matched_players

    News.create_news_item(%{
      source: "fantasynerds",
      external_id: external_id,
      slug: slug,
      title: title,
      body: body,
      summary: item["summary"],
      published_date: published_date,
      category: category || "news",
      sentiment: sentiment,
      ai_summary: ai_summary,
      s3_key: s3_key,
      source_url: source_url,
      author: author,
      ai_processed: ai_summary != nil,
      player_ids: player_ids,
      team_ids: team_ids
    })
  end

  defp analyze_with_ai(title, body) do
    excerpt = String.slice(body, 0, 500)

    case PythonBridge.analyze_news(title, excerpt) do
      {:ok, %{"category" => cat, "sentiment" => sent, "summary" => summary}} ->
        {cat, sent, summary}

      {:ok, %{"category" => cat, "sentiment" => sent}} ->
        {cat, sent, nil}

      {:error, reason} ->
        Logger.warning("FetchNewsWorker: AI analysis failed: #{inspect(reason)}")
        {nil, nil, nil}

      _ ->
        {nil, nil, nil}
    end
  end

  defp match_entities_from_text(text, all_players, all_teams) do
    # Extract potential player names: look for capitalized word pairs
    player_name_candidates =
      text
      |> then(&Regex.scan(~r/\b([A-Z][a-z]+(?:\s[A-Z][a-z]+)+)\b/, &1))
      |> Enum.map(fn [full | _] -> full end)
      |> Enum.uniq()

    # Extract potential team references: common team abbreviations and names
    team_name_candidates =
      all_teams
      |> Enum.filter(fn team ->
        abbr = team.abbreviation || ""
        name = team.name || ""
        city = team.city || ""
        full = "#{city} #{name}"

        String.contains?(text, abbr) ||
          String.contains?(text, name) ||
          String.contains?(text, full)
      end)
      |> Enum.map(fn t -> t.name end)

    matched_players = EntityMatcher.match_players(player_name_candidates, all_players)
    matched_teams = EntityMatcher.match_teams(team_name_candidates, all_teams)

    # Also add teams from matched players
    player_team_ids =
      matched_players
      |> Enum.map(& &1.team_id)
      |> Enum.reject(&is_nil/1)

    all_team_ids =
      (Enum.map(matched_teams, & &1.id) ++ player_team_ids)
      |> Enum.uniq()

    {Enum.map(matched_players, & &1.id), all_team_ids}
  end

  # Derive a stable external ID from the article. The API doesn't provide an explicit ID,
  # so we extract the numeric suffix from the article_link (e.g. ".../click-news/1508132")
  # and fall back to a hash of the headline.
  defp extract_external_id(item) do
    link = item["article_link"] || ""

    id_from_link =
      case Regex.run(~r"/(\d+)$", link) do
        [_, id] -> id
        _ -> nil
      end

    cond do
      id_from_link ->
        id_from_link

      item["id"] ->
        to_string(item["id"])

      item["newsId"] ->
        to_string(item["newsId"])

      true ->
        :crypto.hash(:sha256, item["article_headline"] || link)
        |> Base.encode16(case: :lower)
        |> String.slice(0, 16)
    end
  end

  defp parse_article_date(nil), do: nil

  defp parse_article_date(date_str) do
    case Date.from_iso8601(String.slice(date_str, 0, 10)) do
      {:ok, date} -> date
      _ -> nil
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
