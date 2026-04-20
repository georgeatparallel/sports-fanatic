defmodule SportsFanatic.Workers.GeneratePlayerSeoWorker do
  @moduledoc "Generates daily SEO content for players in today's lineups."

  use Oban.Worker,
    queue: :content_generation,
    max_attempts: 3,
    unique: [period: 3600]

  import Ecto.Query
  alias SportsFanatic.Repo
  alias SportsFanatic.Mlb.{Lineup, Player, Team, Pick, HrPick, ScheduledGame}
  alias SportsFanatic.Content.{PlayerDailyContent, ScoutingReport}
  alias SportsFanatic.PythonBridge

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    today = Date.utc_today()

    players = fetch_lineup_players(today)
    Logger.info("Generating player SEO content for #{length(players)} players")

    players
    |> Task.async_stream(
      fn {player, team} -> generate_content(player, team, today) end,
      max_concurrency: 5,
      timeout: 120_000,
      on_timeout: :kill_task
    )
    |> Enum.each(fn
      {:ok, :ok} ->
        :ok

      {:ok, :skipped} ->
        :ok

      {:ok, {:error, player_name, reason}} ->
        Logger.warning("Player SEO failed for #{player_name}: #{inspect(reason)}")

      {:exit, reason} ->
        Logger.warning("Player SEO task exited: #{inspect(reason)}")
    end)

    :ok
  end

  defp fetch_lineup_players(today) do
    from(l in Lineup,
      join: p in Player,
      on: fragment("(? ->> 'nerds_id')::int = ?", p.external_ids, l.player_nerds_id),
      join: t in Team,
      on: p.team_id == t.id,
      where: l.game_date == ^today,
      distinct: p.id,
      select: {p, t}
    )
    |> Repo.all()
  end

  defp generate_content(player, team, today) do
    # Check if content already exists for today
    existing =
      from(pdc in PlayerDailyContent,
        where: pdc.player_id == ^player.id and pdc.content_date == ^today
      )
      |> Repo.one()

    if existing do
      :skipped
    else
      do_generate(player, team, today)
    end
  end

  defp do_generate(player, team, today) do
    start_ms = System.monotonic_time(:millisecond)

    mlb_id = get_in(player.external_ids, ["mlb_id"])

    # Gather prediction data
    hit_pick = fetch_pick(Pick, mlb_id, today)
    hr_pick = fetch_pick(HrPick, mlb_id, today)

    # Latest scouting report
    scouting =
      from(sr in ScoutingReport,
        where: sr.player_id == ^player.id,
        order_by: [desc: sr.report_date],
        limit: 1
      )
      |> Repo.one()

    # Opposing pitcher from scheduled games
    opposing_pitcher = find_opposing_pitcher(team, today)

    # Build request payload
    player_data = %{
      player_name: player.full_name,
      player_position: player.position || "Unknown",
      team_name: team.name,
      team_slug: team.slug,
      player_slug: player.slug,
      bats: player.bats,
      throws: player.throws,
      content_date: Date.to_iso8601(today),
      opposing_pitcher: opposing_pitcher,
      park_factors: nil,
      hit_prediction: format_hit_pick(hit_pick),
      hr_prediction: format_hr_pick(hr_pick),
      scouting_summary: if(scouting, do: scouting.summary, else: nil),
      recent_stats: nil,
      season_stats: nil
    }

    case PythonBridge.generate_player_seo(player_data) do
      {:ok, %{"content" => content}} ->
        elapsed = System.monotonic_time(:millisecond) - start_ms

        canonical = "https://sportsfanatic.com/mlb/players/#{team.slug}/#{player.slug}"

        json_ld = build_json_ld(player, team, content, canonical)

        attrs = %{
          player_id: player.id,
          team_id: team.id,
          content_date: today,
          headline: content["headline"],
          lead_paragraph: content["lead_paragraph"],
          tldr: content["tldr"],
          matchup_analysis: content["matchup_analysis"],
          opposing_pitcher: opposing_pitcher,
          park_factors: content["park_factors"],
          recent_form: content["recent_form"],
          trends: content["trends"] || [],
          projections: content["projections"] || %{},
          faq_items: content["faq_items"] || [],
          meta_description: String.slice(content["meta_description"] || "", 0, 160),
          keywords: content["keywords"] || [],
          json_ld: json_ld,
          model_version: "claude-sonnet-4-20250514",
          generation_ms: elapsed,
          source_data: player_data
        }

        %PlayerDailyContent{}
        |> PlayerDailyContent.changeset(attrs)
        |> Repo.insert(
          on_conflict: :replace_all,
          conflict_target: [:player_id, :content_date]
        )

        :ok

      {:error, reason} ->
        {:error, player.full_name, reason}
    end
  end

  defp fetch_pick(Pick, mlb_id, today) when not is_nil(mlb_id) do
    numeric_id = mlb_id |> to_string() |> String.to_integer()

    from(p in Pick,
      where: p.player_mlb_id == ^numeric_id and p.prediction_date == ^today
    )
    |> Repo.one()
  end

  defp fetch_pick(HrPick, mlb_id, today) when not is_nil(mlb_id) do
    numeric_id = mlb_id |> to_string() |> String.to_integer()

    from(hp in HrPick,
      where: hp.player_mlb_id == ^numeric_id and hp.prediction_date == ^today
    )
    |> Repo.one()
  end

  defp fetch_pick(_, _, _), do: nil

  defp find_opposing_pitcher(team, today) do
    # Find the scheduled game for this team today
    game =
      from(sg in ScheduledGame,
        where:
          sg.game_date == ^today and
            (sg.away_mlb_id == ^(team.external_ids["mlb_id"] || 0) or
               sg.home_mlb_id == ^(team.external_ids["mlb_id"] || 0))
      )
      |> Repo.one()

    if game do
      team_mlb_id = team.external_ids["mlb_id"]

      pitcher_name =
        if game.home_mlb_id == team_mlb_id do
          game.away_probable_pitcher
        else
          game.home_probable_pitcher
        end

      if pitcher_name do
        %{name: pitcher_name, hand: nil, era: nil, whip: nil}
      end
    end
  end

  defp format_hit_pick(nil), do: nil

  defp format_hit_pick(pick) do
    %{
      probability: pick.confidence,
      confidence: pick.prediction,
      vs_team: pick.vs_team
    }
  end

  defp format_hr_pick(nil), do: nil

  defp format_hr_pick(pick) do
    %{
      probability: pick.hr_probability,
      confidence_tier: pick.confidence_tier,
      vs_team: pick.vs_team
    }
  end

  defp build_json_ld(player, team, content, canonical) do
    faq_entities =
      (content["faq_items"] || [])
      |> Enum.map(fn item ->
        %{
          "@type" => "Question",
          "name" => item["question"],
          "acceptedAnswer" => %{
            "@type" => "Answer",
            "text" => item["answer"]
          }
        }
      end)

    %{
      "@context" => "https://schema.org",
      "@graph" => [
        %{
          "@type" => "Person",
          "name" => player.full_name,
          "jobTitle" => "Professional Baseball Player",
          "memberOf" => %{
            "@type" => "SportsTeam",
            "name" => team.name
          },
          "url" => canonical
        },
        %{
          "@type" => "FAQPage",
          "mainEntity" => faq_entities
        }
      ]
    }
  end
end
