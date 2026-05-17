defmodule SportsFanatic.Workers.MainPostWorker do
  @moduledoc """
  Posts one X tweet pair (main body + URL-bearing self-reply).

  Flow:

    1. If `x_agent_enabled` flag is off → `{:ok, :disabled}`.
    2. If `SpendLedger.budget_remaining?/0` returns false → mark post failed
       with `budget_exceeded` and exit.
    3. Compose body via `XContentAgent.compose/1` (Python Bridge).
    4. If `x_agent_approval_required` is on and post.status is `pending`,
       persist composed body and exit awaiting admin approval.
    5. Otherwise call `X.post_tweet/2` for main body, then for the
       URL-bearing self-reply (`allow_url: true`).
    6. On success, enqueue 18 `EngagementWatcherWorker` jobs every 5 min.
  """

  use Oban.Worker,
    queue: :x_agent,
    max_attempts: 3,
    unique: [period: 600, fields: [:args]]

  require Logger

  alias SportsFanatic.Agents.XContentAgent
  alias SportsFanatic.FeatureFlags
  alias SportsFanatic.Repo
  alias SportsFanatic.Workers.EngagementWatcherWorker
  alias SportsFanatic.X
  alias SportsFanatic.X.{Post, SpendLedger}

  @impl true
  def perform(%Oban.Job{args: %{"post_id" => id, "post_type" => post_type}}) do
    cond do
      not FeatureFlags.enabled?("x_agent_enabled") ->
        {:ok, :disabled}

      not SpendLedger.budget_remaining?() ->
        mark_failed(id, "budget_exceeded")
        {:ok, :budget_exceeded}

      true ->
        process(id, post_type)
    end
  end

  defp process(id, post_type) do
    case Repo.get(Post, id) do
      nil ->
        {:ok, :missing_post}

      %Post{status: status} = post when status in ["pending", "approved"] ->
        compose_and_maybe_post(post, post_type)

      %Post{status: status} ->
        Logger.info("MainPostWorker: skipping post #{id} with status #{status}")
        {:ok, :skipped}
    end
  end

  defp compose_and_maybe_post(%Post{} = post, post_type) do
    case XContentAgent.compose(post_type) do
      {:ok, composed} ->
        attrs = %{
          main_body: composed.main_body || "",
          reply_body: composed.reply_body,
          link_url: composed.link_url,
          context: composed.context || %{}
        }

        if FeatureFlags.enabled?("x_agent_approval_required") and post.status == "pending" do
          {:ok, updated} =
            post
            |> Post.changeset(attrs)
            |> Repo.update()

          broadcast({:post_state_change, updated})
          {:ok, :awaiting_approval}
        else
          {:ok, persisted} = post |> Post.changeset(attrs) |> Repo.update()
          do_post(persisted)
        end

      {:error, reason} = err ->
        mark_failed(post.id, "compose_failed:#{inspect_reason(reason)}")
        err
    end
  end

  defp do_post(%Post{} = post) do
    actor = "system"

    case X.post_tweet(post.main_body, actor: actor, allow_url: false) do
      {:ok, %{tweet_id: main_id, cost_mills: main_cost}} ->
        post_reply(post, main_id, main_cost, actor)

      {:error, reason} ->
        mark_failed(post.id, "main_post_failed:#{inspect_reason(reason)}")

        broadcast(
          {:post_state_change, %{post | status: "failed", error_message: inspect_reason(reason)}}
        )

        {:error, reason}
    end
  end

  defp post_reply(%Post{} = post, main_id, main_cost, actor) do
    reply_body = post.reply_body || post.link_url || ""

    if reply_body == "" do
      finalize_posted(post, main_id, nil, main_cost)
    else
      case X.post_tweet(reply_body, actor: actor, allow_url: true, in_reply_to: main_id) do
        {:ok, %{tweet_id: reply_id, cost_mills: reply_cost}} ->
          finalize_posted(post, main_id, reply_id, main_cost + reply_cost)

        {:error, reason} ->
          Logger.warning("MainPostWorker reply failed for post #{post.id}: #{inspect(reason)}")
          # Still treat the post as `posted` since the main tweet went out.
          finalize_posted(post, main_id, nil, main_cost)
      end
    end
  end

  defp finalize_posted(%Post{} = post, main_id, reply_id, total_cost) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, updated} =
      post
      |> Post.changeset(%{
        status: "posted",
        main_tweet_id: main_id,
        reply_tweet_id: reply_id,
        posted_at: now,
        cost_mills: total_cost
      })
      |> Repo.update()

    enqueue_watcher_jobs(updated.id)
    broadcast({:post_state_change, updated})
    {:ok, :posted}
  end

  defp enqueue_watcher_jobs(post_id) do
    Enum.each(1..18, fn iteration ->
      %{"post_id" => post_id, "iteration" => iteration}
      |> EngagementWatcherWorker.new(schedule_in: iteration * 5 * 60)
      |> Oban.insert()
    end)
  end

  defp mark_failed(post_id, reason) do
    case Repo.get(Post, post_id) do
      nil ->
        :ok

      %Post{} = post ->
        post
        |> Post.changeset(%{status: "failed", error_message: reason})
        |> Repo.update()
    end
  end

  defp broadcast(message) do
    if Process.whereis(SportsFanatic.PubSub) do
      Phoenix.PubSub.broadcast(SportsFanatic.PubSub, "admin:x_agent", message)
    end
  rescue
    _ -> :ok
  end

  defp inspect_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp inspect_reason({status, _}) when is_integer(status), do: "http_#{status}"
  defp inspect_reason(_), do: "unknown_error"
end
