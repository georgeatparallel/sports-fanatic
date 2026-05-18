defmodule SportsFanaticWeb.PlayerController do
  use SportsFanaticWeb, :controller

  import Ecto.Query
  alias SportsFanatic.Content.{NewsItem, ScoutingReport}
  alias SportsFanatic.Mlb
  alias SportsFanatic.Mlb.{HrPick, Lineup, Pick, Player, Team}
  alias SportsFanatic.Predictions
  alias SportsFanatic.Repo
  alias SportsFanatic.Scouting

  @valid_categories ~w(
    performance_analysis injury_report trade_rumor prospect_evaluation
    fantasy_value betting_insight general_news
  )

  def index(conn, params) do
    page = String.to_integer(params["page"] || "1")
    per_page = 50
    today = SportsFanatic.DateHelper.today()

    # Fetch today's lineup players with team info
    lineup_query =
      from(l in Lineup,
        where: l.game_date == ^today and not is_nil(l.player_id),
        join: p in Player,
        on: p.id == l.player_id,
        join: t in Team,
        on: p.team_id == t.id,
        where: not is_nil(p.slug) and not is_nil(t.slug),
        order_by: [asc: t.name, asc: l.batting_order],
        select: %{player: p, team: t, position: l.position, batting_order: l.batting_order}
      )

    lineup_players = Repo.all(lineup_query)

    # All players (paginated)
    query =
      from(p in Player,
        join: t in Team,
        on: p.team_id == t.id,
        where: p.status == "active" and not is_nil(p.slug) and not is_nil(t.slug),
        order_by: [asc: p.last_name, asc: p.first_name],
        select: %{player: p, team: t},
        offset: ^((page - 1) * per_page),
        limit: ^per_page
      )

    players = Repo.all(query)
    total = Repo.aggregate(from(p in Player, where: p.status == "active"), :count)

    conn
    |> assign(:page_title, "MLB Players - Stats & Analysis | Sports Fan Agent")
    |> assign(
      :meta_description,
      "Browse all MLB players with stats, scouting reports, and analysis. Find your favorite player."
    )
    |> assign(:canonical_url, SportsFanaticWeb.SEO.absolute_url("/mlb/players"))
    |> render(:index,
      players: players,
      lineup_players: lineup_players,
      today: today,
      page: page,
      per_page: per_page,
      total: total
    )
  end

  def show(conn, %{"team_slug" => team_slug, "player_slug" => player_slug}) do
    team = Repo.get_by!(Team, slug: team_slug)

    player =
      Player
      |> where([p], p.team_id == ^team.id and p.slug == ^player_slug)
      |> Repo.one!()

    today = SportsFanatic.DateHelper.today()

    # Latest scouting report — check for today first, then any recent
    scouting =
      ScoutingReport
      |> where([sr], sr.player_id == ^player.id)
      |> order_by([sr], desc: sr.report_date)
      |> limit(1)
      |> Repo.one()

    # If no report exists for today, trigger on-demand generation
    scouting_pending =
      if is_nil(scouting) or Date.compare(scouting.report_date, today) != :eq do
        # Enqueue generation (Oban unique constraint prevents duplicates)
        %{"player_id" => player.id}
        |> SportsFanatic.Workers.GenerateScoutingOnDemandWorker.new()
        |> Oban.insert()

        true
      else
        false
      end

    # Today's game card (sourced from mlb.scheduled_games, cached daily)
    game_card = Mlb.todays_game_for_player(player, today)

    # Today's predictions
    mlb_id = get_in(player.external_ids, ["mlb_id"])

    hit_pick =
      if mlb_id do
        parsed_id = String.to_integer(to_string(mlb_id))

        Pick
        |> where([p], p.player_mlb_id == ^parsed_id and p.prediction_date == ^today)
        |> Repo.one()
      end

    hr_pick =
      if mlb_id do
        parsed_id = String.to_integer(to_string(mlb_id))

        HrPick
        |> where([hp], hp.player_mlb_id == ^parsed_id and hp.prediction_date == ^today)
        |> Repo.one()
      end

    today_hit_prediction =
      if mlb_id do
        parsed_id = String.to_integer(to_string(mlb_id))
        Predictions.get_for_player(parsed_id, today)
      end

    # Player news
    news =
      NewsItem
      |> where([n], ^player.id in n.player_ids)
      |> order_by([n], desc: n.published_date)
      |> limit(5)
      |> Repo.all()

    # Categories that have source content (for Quick Links)
    scouting_categories = Scouting.categories_for_player(player.id)

    canonical = SportsFanaticWeb.SEO.absolute_url("/mlb/players/#{team_slug}/#{player_slug}")

    json_ld = %{
      "@context" => "https://schema.org",
      "@type" => "Person",
      "name" => player.full_name,
      "jobTitle" => "Professional Baseball Player",
      "memberOf" => %{
        "@type" => "SportsTeam",
        "name" => team.name
      },
      "url" => canonical
    }

    conn
    |> assign(
      :page_title,
      "#{player.full_name} - #{team.name} | Stats, Scouting & Analysis | Sports Fan Agent"
    )
    |> assign(
      :meta_description,
      String.slice(
        "#{player.full_name} of the #{team.name}. View stats, AI scouting report, hit predictions, and analysis.",
        0,
        160
      )
    )
    |> assign(:canonical_url, canonical)
    |> assign(:og_type, "profile")
    |> assign(:json_ld, Jason.encode!(json_ld))
    |> render(:show,
      player: player,
      team: team,
      scouting: scouting,
      scouting_pending: scouting_pending,
      hit_pick: hit_pick,
      hr_pick: hr_pick,
      game_card: game_card,
      today_hit_prediction: today_hit_prediction,
      news: news,
      scouting_categories: scouting_categories
    )
  end

  def sources(conn, %{
        "team_slug" => team_slug,
        "player_slug" => player_slug,
        "category" => category
      }) do
    unless category in @valid_categories do
      raise Ecto.NoResultsError, queryable: category
    end

    team = Repo.get_by!(Team, slug: team_slug)

    player =
      Player
      |> where([p], p.team_id == ^team.id and p.slug == ^player_slug)
      |> Repo.one!()

    sources = Scouting.sources_for_player_by_category(player.id, category)
    scouting_categories = Scouting.categories_for_player(player.id)

    canonical =
      SportsFanaticWeb.SEO.absolute_url(
        "/mlb/players/#{team_slug}/#{player_slug}/sources/#{category}"
      )

    category_label = SportsFanaticWeb.PlayerHTML.category_label(category)

    json_ld = %{
      "@context" => "https://schema.org",
      "@type" => "CollectionPage",
      "name" => "#{player.full_name} - #{category_label} Sources",
      "description" =>
        "#{category_label} sources and analysis for #{player.full_name} of the #{team.name}.",
      "url" => canonical
    }

    conn
    |> assign(
      :page_title,
      "#{player.full_name} - #{category_label} | Sports Fan Agent"
    )
    |> assign(
      :meta_description,
      String.slice(
        "#{category_label} sources and analysis for #{player.full_name} of the #{team.name}.",
        0,
        160
      )
    )
    |> assign(:canonical_url, canonical)
    |> assign(:json_ld, Jason.encode!(json_ld))
    |> render(:sources,
      player: player,
      team: team,
      sources: sources,
      category: category,
      category_label: category_label,
      scouting_categories: scouting_categories
    )
  end
end
