defmodule SportsFanatic.X.TeamMagazine do
  @moduledoc """
  Context for the per-team daily magazine. Idempotent generator per
  `(team_id, run_date)` with rotation logic for which team gets the daily
  X Agent post.

  All LLM-sourced strings are sanitized via `HtmlSanitizeEx.strip_tags/1`
  before INSERT.
  """

  import Ecto.Query
  require Logger

  alias SportsFanatic.Content.TeamMagazine
  alias SportsFanatic.DateHelper
  alias SportsFanatic.ExternalApis.Exa
  alias SportsFanatic.Mlb.{Lineup, ScheduledGame, Team}
  alias SportsFanatic.PythonBridge
  alias SportsFanatic.Repo

  @doc """
  Idempotent generator. On miss, calls the Python Bridge generator. Caches
  the result for 30 minutes.
  """
  @spec generate_or_fetch(team_slug :: String.t()) ::
          {:ok, %{magazine: TeamMagazine.t(), team: Team.t()}}
          | {:error, :not_found | term()}
  def generate_or_fetch(team_slug) when is_binary(team_slug) do
    today_et = DateHelper.today()

    with {:ok, %Team{} = team} <- find_team_by_slug(team_slug) do
      case Repo.get_by(TeamMagazine, team_id: team.id, run_date: today_et) do
        %TeamMagazine{} = magazine ->
          {:ok, %{magazine: magazine, team: team, cache_hit: true}}

        nil ->
          do_generate(team, today_et)
      end
    end
  end

  @doc """
  Deterministically picks today's team for the rotation. Uses
  `Date.to_gregorian_days/1` mod team count over teams sorted by slug.
  Same date always returns same team.
  """
  @spec rotation_team_for(date :: Date.t()) ::
          {:ok, %{slug: String.t(), team: Team.t()}} | {:error, :no_teams}
  def rotation_team_for(%Date{} = date) do
    teams =
      Repo.all(
        from t in Team,
          order_by: [asc: t.slug],
          select: t
      )

    case teams do
      [] ->
        {:error, :no_teams}

      _ ->
        idx = rem(Date.to_gregorian_days(date), length(teams))
        team = Enum.at(teams, idx)
        {:ok, %{slug: team.slug, team: team}}
    end
  end

  # ── private ─────────────────────────────────────────────────

  defp find_team_by_slug(slug) do
    case Repo.one(from t in Team, where: t.slug == ^slug, limit: 1) do
      nil -> {:error, :not_found}
      %Team{} = team -> {:ok, team}
    end
  end

  defp do_generate(%Team{} = team, today_et) do
    scheduled = today_scheduled_game(team, today_et)
    lineup = today_lineup(team, today_et)

    exa =
      "#{team.name} #{Date.to_iso8601(today_et)}"
      |> safe_exa_search(5)
      |> Exa.dedup_by_domain(2)

    injury_watch = []

    payload_team = %{
      id: team.id,
      name: team.name,
      city: Map.get(team, :city),
      slug: team.slug,
      league: Map.get(team, :league),
      abbreviation: Map.get(team, :abbreviation)
    }

    case PythonBridge.generate_team_magazine(payload_team, scheduled, lineup, exa, injury_watch) do
      {:ok, %{} = body} ->
        insert_and_cache(body, team, today_et)

      {:error, reason} ->
        Logger.warning("Team magazine generation failed for #{team.slug}: #{inspect(reason)}")
        {:error, :generation_failed}
    end
  end

  defp today_scheduled_game(%Team{name: team_name}, today_et) do
    case Repo.one(
           from g in ScheduledGame,
             where: g.game_date == ^today_et,
             where: g.home_name == ^team_name or g.away_name == ^team_name,
             limit: 1
         ) do
      nil ->
        nil

      %ScheduledGame{} = g ->
        Map.take(
          g,
          [
            :game_datetime,
            :game_date,
            :home_name,
            :away_name,
            :venue_name,
            :home_probable_pitcher,
            :away_probable_pitcher
          ]
        )
    end
  end

  defp today_lineup(%Team{abbreviation: abbreviation}, today_et) when is_binary(abbreviation) do
    Repo.all(
      from l in Lineup,
        where: l.game_date == ^today_et and l.team_code == ^abbreviation,
        order_by: [asc: l.batting_order],
        select: %{
          player_name: l.player_name,
          batting_order: l.batting_order,
          position: l.position
        }
    )
  rescue
    _ -> []
  end

  defp today_lineup(_, _), do: []

  defp safe_exa_search(query, num_results) do
    case Exa.search(query, num_results: num_results) do
      {:ok, results} when is_list(results) -> results
      _ -> []
    end
  rescue
    _ -> []
  end

  defp insert_and_cache(body, team, today_et) do
    attrs = %{
      team_id: team.id,
      run_date: today_et,
      state_of_the_team: sanitize(body["state_of_the_team"]) || "",
      today_at_a_glance: sanitize_bullets(body["today_at_a_glance"]),
      game_summary_prose: sanitize(body["game_summary_prose"]),
      sources: sanitize_sources(body["sources"]),
      model: body["model"] |> to_s_or_nil(),
      ai_processed: true
    }

    case %TeamMagazine{}
         |> TeamMagazine.changeset(attrs)
         |> Repo.insert(
           on_conflict: {:replace_all_except, [:id, :inserted_at]},
           conflict_target: [:team_id, :run_date]
         ) do
      {:ok, magazine} ->
        {:ok, %{magazine: magazine, team: team, cache_hit: false}}

      {:error, changeset} ->
        Logger.warning("Team magazine insert failed: #{inspect(changeset.errors)}")
        {:error, :insert_failed}
    end
  end

  defp sanitize(nil), do: nil
  defp sanitize(s) when is_binary(s), do: HtmlSanitizeEx.strip_tags(s)
  defp sanitize(_), do: nil

  defp sanitize_bullets(nil), do: []

  defp sanitize_bullets(list) when is_list(list) do
    list
    |> Enum.map(&sanitize/1)
    |> Enum.reject(&is_nil/1)
  end

  defp sanitize_bullets(_), do: []

  defp sanitize_sources(nil), do: []

  defp sanitize_sources(list) when is_list(list) do
    Enum.map(list, fn
      %{} = src ->
        %{
          "title" => sanitize(src["title"] || Map.get(src, :title)),
          "url" => sanitize_url(src["url"] || Map.get(src, :url)),
          "domain" => sanitize(src["domain"] || Map.get(src, :domain)),
          "published_at" => sanitize(src["published_at"] || Map.get(src, :published_at))
        }

      _ ->
        %{}
    end)
  end

  defp sanitize_sources(_), do: []

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
