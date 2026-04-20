defmodule SportsFanaticWeb.PlayerController do
  use SportsFanaticWeb, :controller

  import Ecto.Query
  alias SportsFanatic.Repo
  alias SportsFanatic.Mlb.{Player, Team, Pick, HrPick}
  alias SportsFanatic.Content.{ScoutingReport, NewsItem, PlayerDailyContent}
  alias SportsFanatic.Cache

  def index(conn, params) do
    page = String.to_integer(params["page"] || "1")
    per_page = 50

    query =
      from(p in Player,
        join: t in Team,
        on: p.team_id == t.id,
        where: not is_nil(p.slug) and not is_nil(t.slug),
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
    |> render(:index,
      players: players,
      page: page,
      per_page: per_page,
      total: total
    )
  end

  def show(conn, %{"team_slug" => team_slug, "player_slug" => player_slug}) do
    cache_key = "sf:page:player:#{team_slug}:#{player_slug}"

    case Cache.get(cache_key) do
      {:ok, cached} when not is_nil(cached) ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(200, cached)

      _ ->
        conn = do_player_show(conn, team_slug, player_slug)

        if conn.status == 200 do
          Cache.set(cache_key, conn.resp_body, 300)
        end

        conn
    end
  end

  defp do_player_show(conn, team_slug, player_slug) do
    team = Repo.get_by!(Team, slug: team_slug)

    player =
      from(p in Player,
        where: p.team_id == ^team.id and p.slug == ^player_slug
      )
      |> Repo.one!()

    today = Date.utc_today()

    # Latest scouting report preview
    scouting =
      from(sr in ScoutingReport,
        where: sr.player_id == ^player.id,
        order_by: [desc: sr.report_date],
        limit: 1
      )
      |> Repo.one()

    # Today's predictions
    mlb_id = get_in(player.external_ids, ["mlb_id"])

    hit_pick =
      if mlb_id do
        from(p in Pick,
          where:
            p.player_mlb_id == ^String.to_integer(to_string(mlb_id)) and
              p.prediction_date == ^today
        )
        |> Repo.one()
      end

    hr_pick =
      if mlb_id do
        from(hp in HrPick,
          where:
            hp.player_mlb_id == ^String.to_integer(to_string(mlb_id)) and
              hp.prediction_date == ^today
        )
        |> Repo.one()
      end

    # Today's AI-generated daily content
    daily_content =
      from(pdc in PlayerDailyContent,
        where: pdc.player_id == ^player.id and pdc.content_date == ^today
      )
      |> Repo.one()

    # Player news
    news =
      from(n in NewsItem,
        where: ^player.id in n.player_ids,
        order_by: [desc: n.published_date],
        limit: 5
      )
      |> Repo.all()

    canonical = "https://sportsfanatic.com/mlb/players/#{team_slug}/#{player_slug}"

    # Use daily content for enhanced SEO when available
    {page_title, meta_description, json_ld} =
      if daily_content do
        {
          "#{daily_content.headline} | Sports Fan Agent",
          daily_content.meta_description,
          daily_content.json_ld
        }
      else
        {
          "#{player.full_name} - #{team.name} | Stats, Scouting & Analysis | Sports Fan Agent",
          String.slice(
            "#{player.full_name} of the #{team.name}. View stats, AI scouting report, hit predictions, and analysis.",
            0,
            160
          ),
          %{
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
        }
      end

    conn
    |> assign(:page_title, page_title)
    |> assign(:meta_description, meta_description)
    |> assign(:canonical, canonical)
    |> assign(:json_ld, json_ld)
    |> render(:show,
      player: player,
      team: team,
      scouting: scouting,
      hit_pick: hit_pick,
      hr_pick: hr_pick,
      news: news,
      daily_content: daily_content
    )
  end
end
