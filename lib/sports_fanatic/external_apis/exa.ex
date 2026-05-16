defmodule SportsFanatic.ExternalApis.Exa do
  @moduledoc """
  Direct HTTP client for the Exa.ai search API.
  Used by the chatbot agent to discover external MLB news articles.
  """

  require Logger

  @base_url "https://api.exa.ai"
  @timeout 15_000

  @doc """
  Searches Exa.ai for news articles matching the given query.

  ## Options
    * `:num_results` - Number of results (default: 5, max: 10)
    * `:days_back` - How many days back to search (default: 7)

  Returns `{:ok, results}` or `{:error, reason}`.
  """
  def search(query, opts \\ []) when is_binary(query) do
    api_key = get_api_key()

    if is_nil(api_key) or api_key == "" do
      Logger.warning("Exa API key not configured, skipping search")
      {:ok, []}
    else
      num_results = Keyword.get(opts, :num_results, 10) |> min(25)
      days_back = Keyword.get(opts, :days_back, 7)

      start_date =
        Date.utc_today()
        |> Date.add(-days_back)
        |> Date.to_iso8601()
        |> Kernel.<>("T00:00:00.000Z")

      body = %{
        query: query,
        numResults: num_results,
        startPublishedDate: start_date,
        type: "neural",
        useAutoprompt: true,
        contents: %{
          text: %{maxCharacters: 2000},
          highlights: true
        },
        category: "news"
      }

      case Req.post("#{@base_url}/search",
             json: body,
             headers: [
               {"x-api-key", api_key},
               {"content-type", "application/json"}
             ],
             receive_timeout: @timeout
           ) do
        {:ok, %Req.Response{status: 200, body: %{"results" => results}}} ->
          parsed =
            Enum.map(results, fn r ->
              %{
                title: r["title"] || "",
                url: r["url"] || "",
                author: r["author"],
                published_date: r["publishedDate"],
                text: get_in(r, ["text"]) || "",
                highlights: r["highlights"] || [],
                score: r["score"]
              }
            end)
            |> Enum.filter(&valid_url?(&1.url))

          {:ok, parsed}

        {:ok, %Req.Response{status: status, body: body}} ->
          Logger.error("Exa API error: status=#{status} body=#{inspect(body)}")
          {:error, {:api_error, status}}

        {:error, reason} ->
          Logger.error("Exa API request failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp get_api_key do
    Application.get_env(:sports_fanatic, :exa, [])[:api_key]
  end

  # Only allow http/https URLs to prevent javascript: and data: injection
  defp valid_url?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme} when scheme in ["http", "https"] -> true
      _ -> false
    end
  end

  defp valid_url?(_), do: false
end
