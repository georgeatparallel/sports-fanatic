defmodule SportsFanatic.X.InjuryReport do
  @moduledoc """
  Context for the public `/mlb/injury-report` page and per-player generation.

  Reads `content.news_items` filtered by injury categories; joins to today's
  `mlb.lineups` to flag `in_lineup_today?`. Generation goes through the
  Python Bridge `/injury-report/generate` endpoint and persists into
  `content.injury_reports` (idempotent on `(player_id, run_date)`).

  All free-text strings stored in `content.injury_reports` are sanitized via
  `HtmlSanitizeEx.strip_tags/1` BEFORE insert. Templates use `<%= ... %>`.
  """

  import Ecto.Query
  require Logger

  alias SportsFanatic.Content.{InjuryReport, NewsItem}
  alias SportsFanatic.DateHelper
  alias SportsFanatic.ExternalApis.Exa
  alias SportsFanatic.Mlb.{Lineup, Player}
  alias SportsFanatic.PythonBridge
  alias SportsFanatic.Repo

  @injury_categories ~w(injury_new injury_worsening injury_update injury_recovery injury_cleared)

  @doc """
  Lists per-player flattened classification trails for the last 3 days.

  Returns a list of:

      %{
        player: Player.t(),
        team: Team.t() | nil,
        in_lineup_today: boolean(),
        trail: [%{date: Date.t(), category: String.t(),
                  injury_grade: String.t() | nil,
                  injury_area: String.t() | nil,
                  summary: String.t(),
                  source_url: String.t() | nil}]
      }

  Ordered by `[in_lineup_today desc, last_published desc]`.
  """
  @spec list_for_today() :: [map()]
  def list_for_today do
    today_et = DateHelper.today()
    cutoff = Date.add(today_et, -3)

    lineup_player_ids = today_lineup_player_ids(today_et)

    news =
      Repo.all(
        from n in NewsItem,
          where: n.category in ^@injury_categories,
          where: n.published_date >= ^cutoff,
          select: %{
            player_ids: n.player_ids,
            published_at: n.published_at,
            published_date: n.published_date,
            category: n.category,
            injury_area: n.injury_area,
            injury_grade: n.injury_grade,
            ai_summary: n.ai_summary,
            summary: n.summary,
            source_url: n.source_url
          }
      )

    player_to_trail = build_player_trails(news)

    player_ids = Map.keys(player_to_trail)

    players_by_id =
      if player_ids == [] do
        %{}
      else
        Repo.all(
          from p in Player,
            where: p.id in ^player_ids,
            preload: [:team]
        )
        |> Map.new(&{&1.id, &1})
      end

    player_to_trail
    |> Enum.map(fn {player_id, trail} ->
      sorted_trail = Enum.sort_by(trail, & &1.date, {:desc, Date})
      last_published = sorted_trail |> List.first() |> Map.get(:date)

      %{
        player: Map.get(players_by_id, player_id),
        team: get_team(players_by_id, player_id),
        in_lineup_today: MapSet.member?(lineup_player_ids, player_id),
        trail: sorted_trail,
        last_published: last_published
      }
    end)
    |> Enum.reject(&is_nil(&1.player))
    |> Enum.sort_by(
      fn row -> {row.in_lineup_today, row.last_published} end,
      :desc
    )
  end

  @doc """
  Idempotent generator. On miss, calls Python Bridge `/injury-report/generate`,
  sanitizes every string, INSERTs, caches.

  Returns `{:ok, %{report: InjuryReport.t(), player: Player.t(), team: Team.t() | nil}}`
  or `{:error, reason}`.
  """
  @spec generate_or_fetch(player_slug :: String.t()) ::
          {:ok, map()} | {:error, :not_found | term()}
  def generate_or_fetch(player_slug) when is_binary(player_slug) do
    today_et = DateHelper.today()

    with {:ok, %Player{} = player} <- find_player_by_slug(player_slug),
         player <- Repo.preload(player, :team) do
      case Repo.get_by(InjuryReport, player_id: player.id, run_date: today_et) do
        %InjuryReport{} = report ->
          {:ok, %{report: report, player: player, team: player.team, cache_hit: true}}

        nil ->
          do_generate(player, today_et)
      end
    end
  end

  @doc """
  Returns up to 5 of the most newsworthy injury status changes in the last
  `hours` hours. Used by `Actions.GenerateInjuryReportPost`.
  """
  @spec recent_status_changes(hours :: integer()) :: [map()]
  def recent_status_changes(hours) when is_integer(hours) and hours > 0 do
    cutoff = DateTime.utc_now() |> DateTime.add(-hours * 3600, :second)

    Repo.all(
      from n in NewsItem,
        where: n.category in ^@injury_categories,
        where:
          (not is_nil(n.published_at) and n.published_at >= ^cutoff) or
            (is_nil(n.published_at) and n.published_date >= ^Date.utc_today()),
        order_by: [desc: coalesce(n.published_at, n.inserted_at)],
        limit: 50,
        select: %{
          player_ids: n.player_ids,
          team_ids: n.team_ids,
          category: n.category,
          injury_grade: n.injury_grade,
          injury_area: n.injury_area,
          summary: n.ai_summary,
          published_at: coalesce(n.published_at, n.inserted_at)
        }
    )
    |> Enum.flat_map(fn n ->
      Enum.map(n.player_ids || [], fn pid ->
        %{
          player_id: pid,
          category: n.category,
          to_status: n.injury_grade,
          injury_area: n.injury_area,
          summary: n.summary,
          published_at: n.published_at
        }
      end)
    end)
    |> Enum.uniq_by(& &1.player_id)
    |> Enum.take(5)
  end

  # ── private ─────────────────────────────────────────────────

  defp today_lineup_player_ids(date) do
    Repo.all(
      from l in Lineup,
        where: l.game_date == ^date and not is_nil(l.player_id),
        distinct: true,
        select: l.player_id
    )
    |> MapSet.new()
  end

  defp build_player_trails(news_rows) do
    Enum.reduce(news_rows, %{}, fn n, acc ->
      entry = %{
        date: n.published_date || (n.published_at && DateTime.to_date(n.published_at)),
        category: n.category,
        injury_grade: n.injury_grade,
        injury_area: n.injury_area,
        summary: n.ai_summary || n.summary || "",
        source_url: n.source_url
      }

      Enum.reduce(n.player_ids || [], acc, fn pid, inner ->
        Map.update(inner, pid, [entry], &[entry | &1])
      end)
    end)
  end

  defp get_team(players_by_id, player_id) do
    case Map.get(players_by_id, player_id) do
      %Player{team: team} -> team
      _ -> nil
    end
  end

  defp find_player_by_slug(slug) do
    case Repo.one(from p in Player, where: p.slug == ^slug, limit: 1) do
      nil -> {:error, :not_found}
      %Player{} = player -> {:ok, player}
    end
  end

  defp do_generate(player, today_et) do
    cutoff = Date.add(today_et, -3)

    local_news =
      Repo.all(
        from n in NewsItem,
          where: n.category in ^@injury_categories,
          where: ^player.id in n.player_ids,
          where: n.published_date >= ^cutoff,
          order_by: [desc: n.published_at],
          limit: 30,
          select: %{
            published_at: n.published_at,
            category: n.category,
            injury_area: n.injury_area,
            injury_grade: n.injury_grade,
            title: n.title,
            ai_summary: n.ai_summary,
            source_url: n.source_url
          }
      )

    exa =
      "#{player.full_name} injury"
      |> safe_exa_search(5)
      |> Exa.dedup_by_domain(2)

    case PythonBridge.generate_injury_report(player_payload(player), local_news, exa) do
      {:ok, %{} = body} ->
        insert_and_cache(body, player, today_et)

      {:error, reason} ->
        Logger.warning("Injury report generation failed for #{player.slug}: #{inspect(reason)}")
        {:error, :generation_failed}
    end
  end

  defp player_payload(player) do
    team = player.team

    %{
      id: player.id,
      full_name: player.full_name,
      team_id: team && team.id,
      team_name: team && team.name,
      team_abbreviation: team && team.abbreviation
    }
  end

  defp safe_exa_search(query, num_results) do
    case Exa.search(query, num_results: num_results) do
      {:ok, results} when is_list(results) -> results
      _ -> []
    end
  rescue
    _ -> []
  end

  defp insert_and_cache(body, player, today_et) do
    attrs = %{
      player_id: player.id,
      run_date: today_et,
      tldr: sanitize(body["tldr"]) || "",
      current_status: clamp_status(body["current_status"]),
      timeline: sanitize_timeline(body["timeline"]),
      expected_return: sanitize(body["expected_return"]),
      fantasy_impact: sanitize(body["fantasy_impact"]),
      sources: sanitize_sources(body["sources"]),
      model: body["model"] |> to_s_or_nil(),
      ai_processed: true
    }

    case %InjuryReport{}
         |> InjuryReport.changeset(attrs)
         |> Repo.insert(
           on_conflict: {:replace_all_except, [:id, :inserted_at]},
           conflict_target: [:player_id, :run_date]
         ) do
      {:ok, report} ->
        {:ok, %{report: report, player: player, team: player.team, cache_hit: false}}

      {:error, changeset} ->
        Logger.warning("Injury report insert failed: #{inspect(changeset.errors)}")
        {:error, :insert_failed}
    end
  end

  defp clamp_status(s) when is_binary(s) do
    if s in InjuryReport.valid_statuses(), do: s, else: "unknown"
  end

  defp clamp_status(_), do: "unknown"

  defp sanitize(nil), do: nil
  defp sanitize(s) when is_binary(s), do: HtmlSanitizeEx.strip_tags(s)
  defp sanitize(_), do: nil

  defp sanitize_timeline(nil), do: []
  defp sanitize_timeline(list) when is_list(list), do: Enum.map(list, &sanitize_entry/1)
  defp sanitize_timeline(_), do: []

  defp sanitize_entry(%{} = entry) do
    %{
      "date" => sanitize(entry["date"]) || sanitize(Map.get(entry, :date)),
      "event" => sanitize(entry["event"]) || sanitize(Map.get(entry, :event)),
      "source_url" => sanitize_url(entry["source_url"] || Map.get(entry, :source_url))
    }
  end

  defp sanitize_entry(_), do: %{}

  defp sanitize_sources(nil), do: []
  defp sanitize_sources(list) when is_list(list), do: Enum.map(list, &sanitize_source/1)
  defp sanitize_sources(_), do: []

  defp sanitize_source(%{} = source) do
    %{
      "title" => sanitize(source["title"] || Map.get(source, :title)),
      "url" => sanitize_url(source["url"] || Map.get(source, :url)),
      "domain" => sanitize(source["domain"] || Map.get(source, :domain)),
      "published_at" => sanitize(source["published_at"] || Map.get(source, :published_at))
    }
  end

  defp sanitize_source(_), do: %{}

  defp sanitize_url(nil), do: nil

  defp sanitize_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme} when scheme in ["http", "https"] -> url
      _ -> nil
    end
  end

  defp sanitize_url(_), do: nil

  defp to_s_or_nil(nil), do: nil
  defp to_s_or_nil(s) when is_binary(s), do: s
  defp to_s_or_nil(s), do: to_string(s)
end
