defmodule SportsFanatic.PythonBridge do
  @moduledoc """
  HTTP client for the (narrowed) Python bridge FastAPI service.

  After the Elixir-native hit-predictions migration the Python bridge only
  serves:

    * `/inference/hit`      — ML inference (single endpoint going forward)
    * `/news/analyze`       — Claude tool_use news classification
    * `/scouting/search`    — Exa search (via Python)
    * `/scouting/search_multi` — multi-query Exa search (legacy scouting flow)
    * `/scouting/classify`  — Claude content classification (legacy scouting flow)
    * `/scouting/generate`  — Claude prose for scouting reports
    * `/gameday/generate`   — Claude prose for Game Day Magazine
    * `/agents/parse-setting` — Claude Haiku parser for legacy agent settings
    * `/chat/resolve-context`, `/chat/synthesize-research` — Claude calls for chatbot

  Removed (superseded by Elixir):
    * `/predict/hit`, `/predict/hr`
    * `/schedule/*`
    * `/simulation/run`
    * `/agents/execute` (stub)
  """

  alias SportsFanatic.PythonBridge.CircuitBreaker

  @timeout 60_000

  ## --- Inference ----------------------------------------------------------

  @doc """
  Score hits via the Python helper. Lightweight wrapper around the
  `/inference/hit` endpoint used by `SportsFanatic.Predictions.Inference`.
  """
  def score_hits(training_rows, inference_rows) do
    post("/inference/hit", %{
      training_rows: training_rows,
      inference_rows: inference_rows
    })
  end

  ## --- Scouting (Claude / Exa) -------------------------------------------

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

  ## --- News / Agents ------------------------------------------------------

  def analyze_news(headline, excerpt) do
    post("/news/analyze", %{headline: headline, excerpt: excerpt})
  end

  @doc "Parse a natural language agent setting into structured criteria."
  def parse_setting(raw_prompt, context \\ %{}) do
    post("/agents/parse-setting", %{raw_prompt: raw_prompt, context: context})
  end

  ## --- Chat ---------------------------------------------------------------

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

  @doc "Draft a daily X tweet (main + URL-bearing self-reply)."
  def draft_x_post(post_type, context, link_url) do
    post("/x-agent/draft-post", %{
      post_type: post_type,
      context: context,
      link_url: link_url,
      max_main_chars: 270,
      max_reply_chars: 270
    })
  end

  @doc "Draft a single X reply tweet given a target tweet + local facts."
  def draft_x_reply(target_tweet, our_context) do
    post("/x-agent/draft-reply", %{
      target_tweet: target_tweet,
      our_context: our_context,
      max_chars: 270
    })
  end

  @doc "Generate a per-player injury report from local news + Exa research."
  def generate_injury_report(player, local_news_items, exa_results) do
    post("/injury-report/generate", %{
      player: player,
      local_news_items: local_news_items,
      exa_results: exa_results
    })
  end

  @doc "Generate a per-team daily magazine update."
  def generate_team_magazine(team, scheduled_game, lineup, exa_results, injury_watch) do
    post("/team-magazine/generate", %{
      team: team,
      scheduled_game: scheduled_game,
      lineup: lineup,
      exa_results: exa_results,
      injury_watch: injury_watch
    })
  end

  ## --- Health -------------------------------------------------------------

  def health_check do
    base_url = base_url()

    case Req.get("#{base_url}/health", receive_timeout: 5_000) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  ## --- Internals ----------------------------------------------------------

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
