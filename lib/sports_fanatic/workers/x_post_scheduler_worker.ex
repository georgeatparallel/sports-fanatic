defmodule SportsFanatic.Workers.XPostSchedulerWorker do
  @moduledoc """
  Daily 11:30 ET planner. Computes today's 3 jittered post times via
  `SportsFanatic.X.Scheduler.plan_day/2`, upserts the
  `system.x_post_rotation` row, and inserts one `system.x_posts` row
  (`status: "pending"`) per slot — each with a corresponding
  `MainPostWorker` scheduled at the slot time.

  Gated by `x_agent_enabled` feature flag.
  """

  use Oban.Worker,
    queue: :x_agent,
    max_attempts: 3,
    unique: [period: 86_400, fields: [:worker, :args]]

  require Logger

  alias SportsFanatic.DateHelper
  alias SportsFanatic.FeatureFlags
  alias SportsFanatic.Repo
  alias SportsFanatic.Workers.MainPostWorker
  alias SportsFanatic.X.{Post, PostRotation, Scheduler, TeamMagazine}

  @impl true
  def perform(%Oban.Job{}) do
    if FeatureFlags.enabled?("x_agent_enabled") do
      do_perform()
    else
      {:ok, :disabled}
    end
  end

  defp do_perform do
    today_et = DateHelper.today()
    plan = Scheduler.plan_day(today_et)

    rotation_slug =
      case TeamMagazine.rotation_team_for(today_et) do
        {:ok, %{slug: slug}} -> slug
        _ -> nil
      end

    result =
      Repo.transaction(fn ->
        rotation_attrs = %{
          run_date: today_et,
          post_order: plan.post_order,
          scheduled_times: serialize_times(plan.scheduled_times),
          selected_team_slug: rotation_slug,
          skipped_slots: plan.skipped_slots,
          earliest_game_at: plan.earliest_game_at
        }

        {:ok, _rotation} =
          %PostRotation{}
          |> PostRotation.changeset(rotation_attrs)
          |> Repo.insert(
            on_conflict: {:replace_all_except, [:id, :inserted_at]},
            conflict_target: :run_date
          )

        posts =
          Enum.map(plan.scheduled_times, fn {post_type, scheduled_at} ->
            insert_post_and_enqueue(post_type, scheduled_at)
          end)

        posts
      end)

    case result do
      {:ok, posts} ->
        Logger.info("XPostSchedulerWorker scheduled #{length(posts)} posts for #{today_et}")

        broadcast(:plan_updated)
        {:ok, :scheduled}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp insert_post_and_enqueue(post_type, %DateTime{} = scheduled_at) do
    {:ok, post} =
      %Post{}
      |> Post.changeset(%{
        post_type: post_type,
        status: "pending",
        scheduled_at: scheduled_at,
        main_body: "",
        reply_body: nil,
        context: %{}
      })
      |> Repo.insert()

    {:ok, _job} =
      %{"post_id" => post.id, "post_type" => post_type}
      |> MainPostWorker.new(scheduled_at: scheduled_at)
      |> Oban.insert()

    post
  end

  defp serialize_times(times) do
    Map.new(times, fn {k, %DateTime{} = dt} -> {k, DateTime.to_iso8601(dt)} end)
  end

  defp broadcast(message) do
    if Process.whereis(SportsFanatic.PubSub) do
      Phoenix.PubSub.broadcast(SportsFanatic.PubSub, "admin:x_agent", message)
    end
  rescue
    _ -> :ok
  end
end
