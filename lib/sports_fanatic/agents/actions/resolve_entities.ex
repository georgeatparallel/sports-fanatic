defmodule SportsFanatic.Agents.Actions.ResolveEntities do
  @moduledoc """
  Resolves player and team names from text using the EntityMatcher.
  Returns matched player_ids and team_ids.
  """

  use SportsFanatic.Agents.Action,
    name: "resolve_entities",
    description: "Match player and team names in text to database records"

  alias SportsFanatic.Mlb.{Player, Team}
  alias SportsFanatic.News.EntityMatcher
  alias SportsFanatic.Repo

  require Logger

  @impl true
  def run(params, _context) do
    text = Map.fetch!(params, :text)

    all_players = Repo.all(Player)
    all_teams = Repo.all(Team)

    # Extract potential names from the text (simple word-boundary approach)
    words = String.split(text, ~r/[,;.!?\n]+/, trim: true)

    # Try to match two-word and three-word combinations as player names
    potential_names =
      words
      |> Enum.flat_map(fn segment ->
        tokens = String.split(String.trim(segment), ~r/\s+/, trim: true)

        case tokens do
          [_single] ->
            [String.trim(segment)]

          _ ->
            tokens
            |> Enum.chunk_every(2, 1, :discard)
            |> Enum.map(&Enum.join(&1, " "))
        end
      end)
      |> Enum.uniq()

    matched_players = EntityMatcher.match_players(potential_names, all_players)
    matched_teams = EntityMatcher.match_teams(potential_names ++ words, all_teams)

    {:ok,
     %{
       player_ids: Enum.map(matched_players, & &1.id),
       team_ids: Enum.map(matched_teams, & &1.id),
       players: Enum.map(matched_players, &%{id: &1.id, name: &1.full_name}),
       teams: Enum.map(matched_teams, &%{id: &1.id, name: &1.name})
     }}
  rescue
    e ->
      Logger.error("ResolveEntities error: #{inspect(e)}")
      {:ok, %{player_ids: [], team_ids: [], players: [], teams: []}}
  end
end
