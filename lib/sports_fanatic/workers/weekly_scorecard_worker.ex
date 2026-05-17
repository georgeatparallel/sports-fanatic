defmodule SportsFanatic.Workers.WeeklyScorecardWorker do
  @moduledoc """
  Sunday 10:00 ET weekly thread. Posts a 5-tweet thread to X where only the
  third tweet carries the URL to the players archive (single $0.20 cost,
  four $0.015 costs — see `lib/sports_fanatic/x/CLAUDE.md`).

  Each tweet is sent as a reply to the previous one to form a thread.
  Gated by the `x_agent_enabled` flag.
  """

  use Oban.Worker, queue: :x_agent, max_attempts: 3, unique: [period: 604_800]

  require Logger

  alias SportsFanatic.FeatureFlags
  alias SportsFanatic.Repo
  alias SportsFanatic.X
  alias SportsFanatic.X.Post

  @url_position 3

  @impl true
  def perform(%Oban.Job{}) do
    if FeatureFlags.enabled?("x_agent_enabled") do
      do_perform()
    else
      {:ok, :disabled}
    end
  end

  defp do_perform do
    bodies = compose_thread()

    case post_thread(bodies) do
      {:ok, tweet_ids} ->
        record_thread(bodies, tweet_ids)
        {:ok, :posted}

      {:error, reason} ->
        Logger.warning("WeeklyScorecardWorker failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp compose_thread do
    # Static thread for now — Python Bridge integration can replace these
    # bodies with Claude-drafted prose in a follow-up.
    [
      "📊 Weekly recap: how our hit predictions did this week.",
      "Top performers and surprises across all 30 teams. (1/5)",
      "Full board with model accuracy and confidence detail: https://sportsfanatic.com/mlb/players?archive=weekly",
      "What stood out: confidence > 70% picks landed at ~62% accuracy this week.",
      "Thanks for following — back tomorrow with the daily picks. ⚾"
    ]
  end

  defp post_thread(bodies) do
    Enum.reduce_while(Enum.with_index(bodies, 1), {[], nil}, fn {body, idx},
                                                                {acc_ids, parent_id} ->
      allow_url = idx == @url_position

      opts =
        []
        |> Keyword.put(:actor, "system")
        |> Keyword.put(:allow_url, allow_url)
        |> maybe_put_reply(parent_id)

      case X.post_tweet(body, opts) do
        {:ok, %{tweet_id: id}} ->
          {:cont, {[id | acc_ids], id}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:error, reason} -> {:error, reason}
      {ids, _last} -> {:ok, Enum.reverse(ids)}
    end
  end

  defp maybe_put_reply(opts, nil), do: opts
  defp maybe_put_reply(opts, id) when is_binary(id), do: Keyword.put(opts, :in_reply_to, id)

  defp record_thread(bodies, ids) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Enum.zip(bodies, ids)
    |> Enum.with_index(1)
    |> Enum.each(fn {{body, tweet_id}, _idx} ->
      %Post{}
      |> Post.changeset(%{
        post_type: "scorecard",
        status: "posted",
        main_body: body,
        main_tweet_id: tweet_id,
        scheduled_at: now,
        posted_at: now,
        context: %{thread_id: List.first(ids)}
      })
      |> Repo.insert()
    end)
  end
end
