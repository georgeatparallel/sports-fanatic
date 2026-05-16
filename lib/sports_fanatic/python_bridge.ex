defmodule SportsFanatic.PythonBridge do
  @moduledoc """
  HTTP client for the Python bridge FastAPI service.
  Uses circuit breaker pattern for fault tolerance.
  """

  alias SportsFanatic.PythonBridge.CircuitBreaker

  @timeout 60_000

  def predict_hits(players) do
    post("/predict/hit", %{players: players})
  end

  def predict_hrs(players) do
    post("/predict/hr", %{players: players})
  end

  def generate_scouting(player_name, player_id, sources_text) do
    post("/scouting/generate", %{
      player_name: player_name,
      player_id: player_id,
      sources_text: sources_text
    })
  end

  def search_player(player_name) do
    post("/scouting/search", %{player_name: player_name})
  end

  def search_player_multi(player_name) do
    post("/scouting/search_multi", %{player_name: player_name})
  end

  def classify_content(title, text) do
    post("/scouting/classify", %{title: title, text: text})
  end

  def generate_game_day(game_data) do
    post("/gameday/generate", game_data)
  end

  def fetch_schedule(date) do
    post("/schedule/fetch", %{date: date})
  end

  def fetch_mlb_teams do
    post("/schedule/teams", %{})
  end

  def fetch_roster(team_id) do
    post("/schedule/roster", %{team_id: team_id})
  end

  def run_simulation(players, n_simulations \\ 10_000) do
    post("/simulation/run", %{players: players, n_simulations: n_simulations})
  end

  def analyze_news(headline, excerpt) do
    post("/news/analyze", %{headline: headline, excerpt: excerpt})
  end

  @doc "Parse a natural language agent setting into structured criteria."
  def parse_setting(raw_prompt, context \\ %{}) do
    post("/agents/parse-setting", %{raw_prompt: raw_prompt, context: context})
  end

  @doc "Execute agent settings against news data (Phase 2 stub)."
  def execute_agents(settings, date_range) do
    post("/agents/execute", %{settings: settings, date_range: date_range})
  end

  @doc "Resolve chat context: detect topic continuation, resolve pronouns, generate search prompts."
  def resolve_chat_context(query, conversation) do
    post("/chat/resolve-context", %{query: query, conversation: conversation})
  end

  @doc "Synthesize research sources into a rich conversational response."
  def synthesize_research(query, sources, local_summaries \\ []) do
    post("/chat/synthesize-research", %{
      query: query,
      sources: sources,
      local_article_summaries: local_summaries
    })
  end

  def health_check do
    base_url = base_url()

    case Req.get("#{base_url}/health", receive_timeout: 5_000) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp post(path, body) do
    cb_available = Process.whereis(SportsFanatic.PythonBridge.CircuitBreaker) != nil

    if cb_available do
      case CircuitBreaker.check() do
        :open -> {:error, :circuit_open}
        _ -> do_post(path, body, true)
      end
    else
      do_post(path, body, false)
    end
  end

  defp do_post(path, body, use_cb) do
    base_url = base_url()

    case Req.post("#{base_url}#{path}", json: body, receive_timeout: @timeout) do
      {:ok, %{status: 200, body: resp_body}} ->
        if use_cb, do: CircuitBreaker.record_success()
        {:ok, resp_body}

      {:ok, %{status: status, body: resp_body}} ->
        if use_cb, do: CircuitBreaker.record_failure()
        {:error, {status, resp_body}}

      {:error, reason} ->
        if use_cb, do: CircuitBreaker.record_failure()
        {:error, reason}
    end
  end

  defp base_url do
    Application.get_env(:sports_fanatic, :python_bridge_url, "http://localhost:8000")
  end
end
