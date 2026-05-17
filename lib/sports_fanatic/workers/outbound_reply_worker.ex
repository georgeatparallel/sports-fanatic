defmodule SportsFanatic.Workers.OutboundReplyWorker do
  @moduledoc """
  Polls watched accounts for new tweets and, if relevant, posts a reply.

  Gated by **two** feature flags:

    * `x_agent_enabled` — master switch
    * `x_agent_outbound_replies_enabled` — outbound opt-in (default off)

  For each enabled `x_watched_targets` row, fetches the account's recent
  tweets since `last_polled_at`, skips ones we've already replied to, and
  composes a reply via `XReplyAgent`. Successful replies persist a
  `system.x_posts` row with `post_type: "reply"` and update
  `last_polled_at` / `last_reply_at`.

  Runs every 30 minutes during the daytime window (per cron in
  `config/config.exs`).
  """

  use Oban.Worker,
    queue: :x_agent,
    max_attempts: 2,
    unique: [period: 1500]

  require Logger
  import Ecto.Query

  alias SportsFanatic.Agents.XReplyAgent
  alias SportsFanatic.FeatureFlags
  alias SportsFanatic.Repo
  alias SportsFanatic.X
  alias SportsFanatic.X.{Post, WatchedTarget}

  @impl true
  def perform(%Oban.Job{}) do
    cond do
      not FeatureFlags.enabled?("x_agent_enabled") ->
        {:ok, :disabled}

      not FeatureFlags.enabled?("x_agent_outbound_replies_enabled") ->
        {:ok, :outbound_disabled}

      true ->
        do_perform()
    end
  end

  defp do_perform do
    targets =
      Repo.all(
        from t in WatchedTarget,
          where: t.enabled == true,
          order_by: [asc_nulls_first: t.last_polled_at]
      )

    Enum.each(targets, &process_target/1)

    {:ok, %{count: length(targets)}}
  end

  defp process_target(%WatchedTarget{} = target) do
    since = target.last_polled_at || hours_ago(6)

    case X.get_user_recent_tweets(target.handle, since) do
      {:ok, tweets} when is_list(tweets) ->
        Enum.each(tweets, &maybe_reply(target, &1))
        touch_polled(target)

      _ ->
        :skip
    end
  rescue
    err ->
      Logger.info("OutboundReplyWorker target #{target.handle} errored: #{inspect(err)}")
      :error
  end

  defp maybe_reply(%WatchedTarget{} = target, tweet) do
    tweet_id = Map.get(tweet, "id") || Map.get(tweet, :id)

    cond do
      is_nil(tweet_id) -> :skip
      already_replied?(tweet_id) -> :skip
      true -> spawn_reply(target, tweet, tweet_id)
    end
  end

  defp already_replied?(tweet_id) do
    Repo.exists?(
      from p in Post,
        where: p.in_reply_to_tweet_id == ^tweet_id and p.status in ["posted", "failed"]
    )
  end

  defp spawn_reply(%WatchedTarget{} = target, tweet, tweet_id) do
    target_tweet = %{
      "id" => tweet_id,
      "author_handle" => target.handle,
      "text" => Map.get(tweet, "text") || Map.get(tweet, :text, ""),
      "is_inbound" => false
    }

    with {:ok, %{reply_body: body}} <-
           XReplyAgent.draft_for(target_tweet, %{focus: target.focus}),
         {:ok, %{tweet_id: posted_id, cost_mills: cost}} <-
           X.post_tweet(body, actor: "watcher", allow_url: false, in_reply_to: tweet_id) do
      %Post{}
      |> Post.changeset(%{
        post_type: "reply",
        status: "posted",
        main_body: body,
        main_tweet_id: posted_id,
        in_reply_to_tweet_id: tweet_id,
        scheduled_at: DateTime.utc_now() |> DateTime.truncate(:second),
        posted_at: DateTime.utc_now() |> DateTime.truncate(:second),
        cost_mills: cost,
        context: %{target_handle: target.handle}
      })
      |> Repo.insert()

      target
      |> WatchedTarget.changeset(%{
        last_reply_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.update()
    else
      err ->
        Logger.info("OutboundReplyWorker reply not posted for #{target.handle}: #{inspect(err)}")
    end
  end

  defp touch_polled(%WatchedTarget{} = target) do
    target
    |> WatchedTarget.changeset(%{last_polled_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    |> Repo.update()
  end

  defp hours_ago(n) do
    DateTime.utc_now() |> DateTime.add(-n * 3600, :second)
  end
end
