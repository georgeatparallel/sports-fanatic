defmodule SportsFanatic.AI.Claude do
  @moduledoc """
  Direct Elixir client for the Anthropic Claude API.
  Eliminates the Python Bridge hop for chatbot operations,
  cutting latency by ~200ms per call.
  """

  require Logger

  @base_url "https://api.anthropic.com/v1/messages"
  @model "claude-haiku-4-5-20251001"
  @timeout 30_000

  # ── News Classification ────────────────────────────────────

  @classify_tool %{
    "name" => "classify_article",
    "description" => "Classify an MLB news article with category, sentiment, summary, entity extraction, and injury details.",
    "input_schema" => %{
      "type" => "object",
      "properties" => %{
        "category" => %{
          "type" => "string",
          "enum" => ["injury_new", "injury_worsening", "injury_update", "injury_recovery", "injury_cleared", "trade", "performance", "transaction", "news"]
        },
        "sentiment" => %{"type" => "string", "enum" => ["negative", "neutral", "positive"]},
        "summary" => %{"type" => "string"},
        "player_names" => %{"type" => "array", "items" => %{"type" => "string"}},
        "team_names" => %{"type" => "array", "items" => %{"type" => "string"}},
        "injury_area" => %{"type" => "string"},
        "injury_grade" => %{
          "type" => "string",
          "enum" => ["day_to_day", "10_day_il", "15_day_il", "60_day_il", "season_ending", "pending_imaging", "cleared", "rehab_assignment", "unknown"]
        },
        "domain_tags" => %{"type" => "array", "items" => %{"type" => "string"}}
      },
      "required" => ["category", "sentiment", "summary"]
    }
  }

  @classify_system "You are an MLB news classifier. Analyze the article and classify it accurately. For injury articles, determine trajectory (new/worsening/update/recovery/cleared) and set injury_area and injury_grade. For non-injury: transaction (roster moves), performance (stats/streaks), trade (rumors/deals), or news (general). Always provide domain_tags (1-5 lowercase hyphenated tags like streak, home-run, injury, prospect, call-up)."

  def classify_article(headline, excerpt) do
    call_with_tool(
      @classify_system,
      "Classify this article:\n\nHeadline: #{headline}\n\nExcerpt: #{String.slice(excerpt || "", 0, 2000)}",
      @classify_tool,
      "classify_article"
    )
  end

  # ── Context Resolution ─────────────────────────────────────

  @resolve_tool %{
    "name" => "resolve_context",
    "description" => "Analyze a user's chat message in conversation context.",
    "input_schema" => %{
      "type" => "object",
      "properties" => %{
        "is_continuation" => %{"type" => "boolean"},
        "resolved_query" => %{"type" => "string"},
        "entities" => %{"type" => "array", "items" => %{"type" => "string"}},
        "search_prompts" => %{"type" => "array", "items" => %{"type" => "string"}},
        "reasoning" => %{"type" => "string"}
      },
      "required" => ["is_continuation", "resolved_query", "entities", "search_prompts", "reasoning"]
    }
  }

  @resolve_system "You are an MLB research assistant analyzing user queries. Determine if the new message continues the previous topic (pronouns, follow-ups) or starts a new topic (new proper nouns, different subject). Resolve pronouns using context. Generate 2 specific Exa.ai search queries (always include 'MLB' or 'baseball', include '2026' in one)."

  def resolve_context(query, conversation) do
    messages =
      Enum.map(conversation, fn msg ->
        %{"role" => msg.role || msg["role"], "content" => msg.content || msg["content"]}
      end) ++ [%{"role" => "user", "content" => "New user message to analyze: \"#{query}\""}]

    call_with_tool_messages(
      @resolve_system,
      messages,
      @resolve_tool,
      "resolve_context"
    )
  end

  # ── Research Synthesis ─────────────────────────────────────

  @synthesis_system """
  You are a knowledgeable, friendly MLB research assistant. Provide rich, detailed analysis using markdown formatting.

  For injured players: cover current status, return timeline, rehab progress, fantasy implications.
  For active players: recent performance, upcoming matchups, fantasy value, betting angles.
  For teams: key storylines, standings implications, roster moves.

  Use **bold** for section headers, bullet points for lists. Be conversational and enthusiastic.
  Synthesize across sources — don't just list them. End with a brief takeaway. Aim for 200-400 words.
  """

  def synthesize_research(query, sources, local_summaries \\ []) do
    source_text =
      sources
      |> Enum.take(15)
      |> Enum.with_index(1)
      |> Enum.map(fn {src, i} ->
        title = src[:title] || src["title"] || ""
        text = src[:text] || src["text"] || ""
        "--- Source #{i}: #{title} ---\n#{String.slice(text, 0, 2000)}"
      end)
      |> Enum.join("\n\n")

    local_text =
      if local_summaries != [] do
        "\n\nArticles in our database:\n" <> Enum.join(Enum.map(local_summaries, &"- #{&1}"), "\n")
      else
        ""
      end

    prompt = """
    The user asked: "#{query}"

    Source material from web research:#{local_text}

    External sources:
    #{source_text}

    Write a comprehensive, friendly research response using markdown. Do NOT return JSON.
    """

    case call_text(prompt, system: @synthesis_system, max_tokens: 2048, temperature: 0.3) do
      {:ok, text} -> {:ok, %{"response" => text}}
      error -> error
    end
  end

  # ── Low-Level API Calls ────────────────────────────────────

  defp call_with_tool(system, user_content, tool, tool_name) do
    call_with_tool_messages(system, [%{"role" => "user", "content" => user_content}], tool, tool_name)
  end

  defp call_with_tool_messages(system, messages, tool, tool_name) do
    body = %{
      "model" => @model,
      "max_tokens" => 512,
      "temperature" => 0.0,
      "system" => system,
      "messages" => messages,
      "tools" => [tool],
      "tool_choice" => %{"type" => "tool", "name" => tool_name}
    }

    case do_request(body) do
      {:ok, %{"content" => content}} ->
        case Enum.find(content, &(&1["type"] == "tool_use" && &1["name"] == tool_name)) do
          %{"input" => input} -> {:ok, input}
          nil -> {:error, :no_tool_use}
        end

      error ->
        error
    end
  end

  defp call_text(user_content, opts) do
    body = %{
      "model" => @model,
      "max_tokens" => Keyword.get(opts, :max_tokens, 1024),
      "temperature" => Keyword.get(opts, :temperature, 0.0),
      "system" => Keyword.get(opts, :system, ""),
      "messages" => [%{"role" => "user", "content" => user_content}]
    }

    case do_request(body) do
      {:ok, %{"content" => [%{"type" => "text", "text" => text} | _]}} ->
        {:ok, text}

      {:ok, %{"content" => content}} ->
        text = content |> Enum.filter(&(&1["type"] == "text")) |> Enum.map(&(&1["text"])) |> Enum.join("")
        if text != "", do: {:ok, text}, else: {:error, :empty_response}

      error ->
        error
    end
  end

  defp do_request(body) do
    api_key = get_api_key()

    if is_nil(api_key) or api_key == "" do
      Logger.warning("ANTHROPIC_API_KEY not configured for direct Claude calls")
      {:error, :no_api_key}
    else
      case Req.post(@base_url,
             json: body,
             headers: [
               {"x-api-key", api_key},
               {"anthropic-version", "2023-06-01"},
               {"content-type", "application/json"}
             ],
             receive_timeout: @timeout
           ) do
        {:ok, %Req.Response{status: 200, body: response}} ->
          {:ok, response}

        {:ok, %Req.Response{status: status, body: body}} ->
          Logger.error("Claude API error: status=#{status} body=#{inspect(body)}")
          {:error, {:api_error, status}}

        {:error, reason} ->
          Logger.error("Claude API request failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp get_api_key do
    Application.get_env(:sports_fanatic, :anthropic_api_key) ||
      System.get_env("ANTHROPIC_API_KEY")
  end
end
