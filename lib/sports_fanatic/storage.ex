defmodule SportsFanatic.Storage do
  @moduledoc """
  S3 storage for raw news article data.

  Stores JSON payloads under a date-partitioned key structure:
    news/raw/YYYY/MM/DD/{external_id}.json

  Gracefully degrades: if S3 is disabled or fails, returns {:ok, nil}
  so the caller can continue processing without the S3 key.
  """

  require Logger

  @doc """
  Uploads a raw news article payload to S3.

  Returns {:ok, key} on success, {:ok, nil} if S3 is disabled,
  or {:error, reason} on failure.
  """
  def put_news_article(external_id, content) when is_binary(external_id) do
    if s3_enabled?() do
      date = Date.utc_today()
      key = news_article_key(date, external_id)
      bucket = Application.get_env(:sports_fanatic, :news_s3_bucket)

      case ExAws.S3.put_object(bucket, key, Jason.encode!(content),
             content_type: "application/json"
           )
           |> ExAws.request() do
        {:ok, _} ->
          {:ok, key}

        {:error, reason} ->
          Logger.warning("S3 upload failed for #{key}: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:ok, nil}
    end
  end

  @doc """
  Builds the S3 key for a news article given a date and external ID.
  """
  def news_article_key(%Date{} = date, external_id) do
    month = String.pad_leading("#{date.month}", 2, "0")
    day = String.pad_leading("#{date.day}", 2, "0")
    safe_id = sanitize_key(external_id)
    "news/raw/#{date.year}/#{month}/#{day}/#{safe_id}.json"
  end

  @doc """
  Strips all characters except alphanumerics, hyphens, and underscores
  from a key component to prevent path traversal attacks.
  """
  def sanitize_key(id) when is_binary(id) do
    String.replace(id, ~r/[^a-zA-Z0-9_-]/, "")
  end

  def sanitize_key(id), do: sanitize_key(to_string(id))

  defp s3_enabled? do
    Application.get_env(:sports_fanatic, :news_s3_enabled, false)
  end
end
