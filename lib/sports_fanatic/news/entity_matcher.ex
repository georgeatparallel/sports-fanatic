defmodule SportsFanatic.News.EntityMatcher do
  @moduledoc """
  Fuzzy-matches player and team names from news articles against
  the database. Uses String.jaro_distance/2 for approximate matching.
  """

  @player_threshold 0.85
  @team_threshold 0.85

  @doc """
  Matches a list of player name strings against known players.
  Returns a list of matched player structs (with team preloaded).
  """
  def match_players([], _all_players), do: []

  def match_players(player_names, all_players) when is_list(player_names) do
    player_names
    |> Enum.map(&match_player(&1, all_players))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.id)
  end

  @doc """
  Matches a list of team name or abbreviation strings against known teams.
  Tries exact abbreviation match first, then fuzzy name match.
  Returns a list of matched team structs.
  """
  def match_teams([], _all_teams), do: []

  def match_teams(team_names, all_teams) when is_list(team_names) do
    team_names
    |> Enum.map(&match_team(&1, all_teams))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.id)
  end

  defp match_player(name, all_players) when is_binary(name) do
    downcased = String.downcase(name)

    # Try exact match first
    exact =
      Enum.find(all_players, fn p ->
        String.downcase(p.full_name || "") == downcased
      end)

    if exact do
      exact
    else
      # Fuzzy match
      all_players
      |> Enum.map(fn p ->
        score = String.jaro_distance(downcased, String.downcase(p.full_name || ""))
        {p, score}
      end)
      |> Enum.filter(fn {_p, score} -> score >= @player_threshold end)
      |> Enum.max_by(fn {_p, score} -> score end, fn -> nil end)
      |> case do
        {player, _score} -> player
        nil -> nil
      end
    end
  end

  defp match_team(name, all_teams) when is_binary(name) do
    downcased = String.downcase(String.trim(name))

    # Exact abbreviation match first
    exact_abbr =
      Enum.find(all_teams, fn t ->
        String.downcase(t.abbreviation || "") == downcased
      end)

    if exact_abbr do
      exact_abbr
    else
      # Exact name match
      exact_name =
        Enum.find(all_teams, fn t ->
          String.downcase(t.name || "") == downcased
        end)

      if exact_name do
        exact_name
      else
        # Fuzzy name match
        all_teams
        |> Enum.map(fn t ->
          name_score = String.jaro_distance(downcased, String.downcase(t.name || ""))

          full_name =
            String.downcase("#{t.city || ""} #{t.name || ""}" |> String.trim())

          full_score = String.jaro_distance(downcased, full_name)
          {t, max(name_score, full_score)}
        end)
        |> Enum.filter(fn {_t, score} -> score >= @team_threshold end)
        |> Enum.max_by(fn {_t, score} -> score end, fn -> nil end)
        |> case do
          {team, _score} -> team
          nil -> nil
        end
      end
    end
  end
end
