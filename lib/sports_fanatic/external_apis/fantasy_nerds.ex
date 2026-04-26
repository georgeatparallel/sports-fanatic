defmodule SportsFanatic.ExternalApis.FantasyNerds do
  @moduledoc """
  FantasyNerds API client for MLB data.

  Endpoints:
    - Daily lineups
    - Teams
    - Player news
  """

  require Logger

  @base_url "https://api.fantasynerds.com/v1/mlb"
  @timeout 30_000

  def fetch_lineups(game_date) do
    result = get("/lineups", date: game_date)

    case result do
      {:ok, %{"games" => games}} ->
        players = Enum.flat_map(games, &extract_game_lineups/1)
        {:ok, players}

      {:ok, data} ->
        Logger.warning("Unexpected lineups response format: #{inspect(Map.keys(data))}")
        {:ok, []}

      error ->
        error
    end
  end

  defp extract_game_lineups(game) do
    lineups = Map.get(game, "lineups", %{})

    Enum.flat_map(["away", "home"], fn side ->
      team_code = Map.get(game, "#{side}_team", "")
      side_data = Map.get(lineups, side, %{})

      side_data
      |> Map.get("lineup", [])
      |> Enum.map(fn player ->
        %{
          player_id: player["playerId"],
          team_code: team_code,
          batting_order: player["battingOrder"],
          position: player["position"]
        }
      end)
      |> Enum.filter(& &1.player_id)
    end)
  end

  def fetch_teams do
    get("/teams")
  end

  def fetch_news do
    get("/news")
  end

  def fetch_players do
    get("/players")
  end

  defp get(path, params \\ []) do
    api_key = Application.get_env(:sports_fanatic, :fantasy_nerds_api_key)

    if is_nil(api_key) do
      Logger.warning("FantasyNerds API key not configured")
      {:error, :api_key_missing}
    else
      url = @base_url <> path
      params = Keyword.put(params, :apikey, api_key)

      case Req.get(url,
             params: params,
             receive_timeout: @timeout,
             retry: :transient,
             max_retries: 3
           ) do
        {:ok, %{status: 200, body: body}} ->
          {:ok, body}

        {:ok, %{status: status, body: body}} ->
          Logger.error("FantasyNerds API error: #{status} - #{inspect(body)}")
          {:error, {:http_error, status}}

        {:error, reason} ->
          Logger.error("FantasyNerds API request failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end
end
