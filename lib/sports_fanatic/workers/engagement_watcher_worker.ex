defmodule SportsFanatic.Workers.EngagementWatcherWorker do
  @moduledoc """
  Recurring polling worker for one posted X tweet.

  Scheduled by `MainPostWorker` after a successful post — 18 invocations
  every 5 minutes (90 minutes total). Each invocation:

    1. Calls `X.fetch_metrics_and_replies/1` for the main tweet id.
    2. Updates `system.x_posts.engagement_metrics` for the post row.
    3. For each new reply (not yet recorded in `system.x_posts` with the
       same `in_reply_to_tweet_id`), spawns `XReplyAgent.draft_for/2`,
       calls `X.post_tweet/2` with `:in_reply_to`, persists a reply row.

  Hard cap at iteration 18 (no further reschedule).
  """

  use Oban.Worker,
    queue: :x_agent,
    max_attempts: 2,
    unique: [period: 300, fields: [:args]]

  require Logger
  import Ecto.Query

  alias SportsFanatic.Agents.XReplyAgent
  alias SportsFanatic.FeatureFlags
  alias SportsFanatic.Repo
  alias SportsFanatic.X
  alias SportsFanatic.X.Post

  @max_iterations 18

  @impl true
  def perform(%Oban.Job{args: %{"post_id" => post_id, "iteration" => iteration}})
      when is_integer(iteration) do
    if FeatureFlags.enabled?("x_agent_enabled") do
      do_perform(post_id, iteration)
    else
      {:ok, :disabled}
    end
  end

  defp do_perform(post_id, iteration) do
    case Repo.get(Post, post_id) do
      nil ->
        {:ok, :missing_post}

      %Post{main_tweet_id: nil} ->
        {:ok, :no_tweet_yet}

      %Post{main_tweet_id: tweet_id} = post ->
        process_iteration(post, tweet_id, iteration)
    end
  end

  defp process_iteration(%Post{} = post, tweet_id, iteration) do
    case X.fetch_metrics_and_replies(tweet_id) do
      {:ok, %{metrics: metrics, replies: replies}} ->
        update_metrics(post, metrics)
        process_replies(post, replies)

      {:error, reason} ->
        Logger.info(
          "EngagementWatcherWorker fetch failed for #{post.id} iter=#{iteration}: " <>
            inspect(reason)
        )
    end

    if iteration < @max_iterations do
      %{"post_id" => post.id, "iteration" => iteration + 1}
      |> __MODULE__.new(schedule_in: 5 * 60)
      |> Oban.insert()
    end

    {:ok, :polled}
  end

  defp update_metrics(%Post{} = post, %{} = metrics) do
    post
    |> Post.changeset(%{engagement_metrics: metrics})
    |> Repo.update()
  end

  defp update_metrics(_, _), do: :ok

  defp process_replies(%Post{} = post, replies) when is_list(replies) do
    Enum.each(replies, fn reply ->
      reply_id = Map.get(reply, "id") || Map.get(reply, :id)

      cond do
        is_nil(reply_id) ->
          :skip

        already_replied?(reply_id) ->
          :skip

        true ->
          spawn_reply(post, reply, reply_id)
      end
    end)
  end

  defp process_replies(_, _), do: :ok

  defp already_replied?(reply_id) when is_binary(reply_id) do
    Repo.exists?(
      from p in Post,
        where: p.in_reply_to_tweet_id == ^reply_id and p.status in ["posted", "failed"]
    )
  end

  defp already_replied?(_), do: false

  defp spawn_reply(%Post{} = parent, reply, reply_id) do
    target = %{
      "id" => reply_id,
      "author_handle" => Map.get(reply, "author_handle") || Map.get(reply, :author_handle, ""),
      "text" => Map.get(reply, "text") || Map.get(reply, :text, ""),
      "is_inbound" => true
    }

    with {:ok, %{reply_body: body}} <- XReplyAgent.draft_for(target, parent.context || %{}),
         {:ok, %{tweet_id: posted_id, cost_mills: cost}} <-
           X.post_tweet(body, actor: "watcher", allow_url: false, in_reply_to: reply_id) do
      %Post{}
      |> Post.changeset(%{
        post_type: "reply",
        status: "posted",
        main_body: body,
        main_tweet_id: posted_id,
        in_reply_to_tweet_id: reply_id,
        scheduled_at: DateTime.utc_now() |> DateTime.truncate(:second),
        posted_at: DateTime.utc_now() |> DateTime.truncate(:second),
        cost_mills: cost,
        context: %{parent_post_id: parent.id, target: target}
      })
      |> Repo.insert()
    else
      err ->
        Logger.info("EngagementWatcherWorker reply not posted: #{inspect(err)}")
    end
  end
end
