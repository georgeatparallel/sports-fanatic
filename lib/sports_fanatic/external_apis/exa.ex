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

      do_search_with_retry(body, api_key, _attempt = 1)
    end
  end

  @max_retries 3
  @retry_base_ms 500

  defp do_search_with_retry(body, api_key, attempt) do
    case Req.post("#{@base_url}/search",
           json: body,
           headers: [
             {"x-api-key", api_key},
             {"content-type", "application/json"}
           ],
           receive_timeout: @timeout
         ) do
      {:ok, %Req.Response{status: 200, body: %{"results" => results}}} when results != [] ->
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

      {:ok, %Req.Response{status: 200, body: %{"results" => []}}} when attempt < @max_retries ->
        backoff = @retry_base_ms * attempt

        Logger.info(
          "Exa returned 0 results, retrying in #{backoff}ms (attempt #{attempt}/#{@max_retries})"
        )

        Process.sleep(backoff)
        do_search_with_retry(body, api_key, attempt + 1)

      {:ok, %Req.Response{status: 200, body: _}} ->
        {:ok, []}

      {:ok, %Req.Response{status: status}} when attempt < @max_retries ->
        backoff = @retry_base_ms * attempt

        Logger.warning(
          "Exa API error status=#{status}, retrying in #{backoff}ms (attempt #{attempt}/#{@max_retries})"
        )

        Process.sleep(backoff)
        do_search_with_retry(body, api_key, attempt + 1)

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        Logger.error("Exa API error: status=#{status} body=#{inspect(resp_body)}")
        {:error, {:api_error, status}}

      {:error, reason} when attempt < @max_retries ->
        backoff = @retry_base_ms * attempt

        Logger.warning(
          "Exa request failed: #{inspect(reason)}, retrying in #{backoff}ms (attempt #{attempt}/#{@max_retries})"
        )

        Process.sleep(backoff)
        do_search_with_retry(body, api_key, attempt + 1)

      {:error, reason} ->
        Logger.error("Exa API request failed after #{@max_retries} attempts: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Caps Exa search results to at most `max_per_domain` entries per host,
  preserving the input order (which is already ranked by relevance/score).

  Useful when a single domain dominates an Exa response and we want a more
  diverse mix of sources before storing or summarising.

  ## Parameters
    * `results` — list of result maps as returned by `search/2`. Each map is
      expected to have a `:url` key (string).
    * `max_per_domain` — positive integer cap per host. Default `2`.

  Entries whose URL cannot be parsed into a `%URI{host: host}` (host is nil
  or empty) are kept and counted under an empty-string bucket so a flood of
  unparseable URLs is also capped.
  """
  @spec dedup_by_domain([map()], pos_integer()) :: [map()]
  def dedup_by_domain(results, max_per_domain \\ 2)
      when is_list(results) and is_integer(max_per_domain) and max_per_domain > 0 do
    {kept, _counts} =
      Enum.reduce(results, {[], %{}}, fn result, {acc, counts} ->
        host = result_host(result)
        current = Map.get(counts, host, 0)

        if current < max_per_domain do
          {[result | acc], Map.put(counts, host, current + 1)}
        else
          {acc, counts}
        end
      end)

    Enum.reverse(kept)
  end

  defp result_host(%{url: url}) when is_binary(url), do: extract_host(url)
  defp result_host(%{"url" => url}) when is_binary(url), do: extract_host(url)
  defp result_host(_), do: ""

  defp extract_host(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) and host != "" -> String.downcase(host)
      _ -> ""
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
