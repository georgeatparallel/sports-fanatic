defmodule SportsFanatic.Workers.RunNewsAgentsWorker do
  @moduledoc """
  Daily Oban worker that executes news agent settings for all users.
  Runs at 9am ET (13:00 UTC during EDT).

  For each user with active settings, queries news_items matching
  the parsed criteria and stores results. Each user is processed
  independently so failures don't block other users.

  Gated by the `news_agents_enabled` feature flag.
  """

  use Oban.Worker,
    queue: :content_generation,
    max_attempts: 3

  alias SportsFanatic.Agents
  alias SportsFanatic.Content.NewsItem
  alias SportsFanatic.FeatureFlags
  alias SportsFanatic.Repo

  import Ecto.Query

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    if FeatureFlags.enabled?("news_agents_enabled") do
      run_agents()
    else
      Logger.info("RunNewsAgentsWorker: feature flag disabled, skipping")
      :ok
    end
  end

  defp run_agents do
    user_ids = Agents.users_with_active_settings()
    Logger.info("RunNewsAgentsWorker: processing #{length(user_ids)} users")

    today = SportsFanatic.DateHelper.today()
    yesterday = Date.add(today, -1)

    results =
      Enum.map(user_ids, fn user_id ->
        try do
          process_user(user_id, yesterday, today)
        rescue
          error ->
            Logger.error("RunNewsAgentsWorker: failed for user #{user_id}: #{inspect(error)}")

            {:error, user_id}
        end
      end)

    successes = Enum.count(results, &match?(:ok, &1))
    failures = Enum.count(results, &match?({:error, _}, &1))

    Logger.info("RunNewsAgentsWorker: completed. successes=#{successes} failures=#{failures}")

    :ok
  end

  defp process_user(user_id, from_date, to_date) do
    settings = Agents.active_settings_for_user(user_id)

    Enum.each(settings, fn setting ->
      # Mark as running
      Agents.update_setting(setting, %{status: "running"})

      matched_ids = find_matching_news(setting.parsed_criteria, from_date, to_date)

      explanation =
        build_explanation(setting.raw_prompt, length(matched_ids), from_date, to_date)

      # Store result
      Agents.create_result(%{
        user_id: user_id,
        setting_id: setting.id,
        matched_news_item_ids: matched_ids,
        explanation: explanation,
        run_date: to_date
      })

      # Update setting
      Agents.update_setting(setting, %{
        status: "completed",
        last_run_at: DateTime.utc_now(),
        last_result: %{
          "matched_count" => length(matched_ids),
          "run_date" => Date.to_iso8601(to_date)
        }
      })
    end)

    # Broadcast results to user
    Phoenix.PubSub.broadcast(
      SportsFanatic.PubSub,
      "agent:results:#{user_id}",
      {:agent_results, user_id}
    )

    :ok
  end

  defp find_matching_news(nil, _from, _to), do: []

  defp find_matching_news(criteria, from_date, to_date) when is_map(criteria) do
    query =
      NewsItem
      |> where([n], n.published_date >= ^from_date and n.published_date <= ^to_date)

    query = apply_player_filter(query, criteria)
    query = apply_team_filter(query, criteria)
    query = apply_category_filter(query, criteria)
    query = apply_domain_tag_filter(query, criteria)

    query
    |> select([n], n.id)
    |> Repo.all()
  end

  defp apply_player_filter(query, %{"target_players" => players})
       when is_list(players) and players != [] do
    # Build OR conditions using dynamic to avoid breaking the date range WHERE clause
    conditions =
      Enum.reduce(players, dynamic(false), fn player_name, acc ->
        pattern = "%#{sanitize_like(player_name)}%"
        dynamic([n], ^acc or ilike(n.title, ^pattern) or ilike(n.ai_summary, ^pattern))
      end)

    where(query, ^conditions)
  end

  defp apply_player_filter(query, _), do: query

  defp apply_team_filter(query, %{"target_teams" => teams})
       when is_list(teams) and teams != [] do
    conditions =
      Enum.reduce(teams, dynamic(false), fn team_name, acc ->
        pattern = "%#{sanitize_like(team_name)}%"
        dynamic([n], ^acc or ilike(n.title, ^pattern) or ilike(n.ai_summary, ^pattern))
      end)

    where(query, ^conditions)
  end

  defp apply_team_filter(query, _), do: query

  defp apply_category_filter(query, %{"categories" => categories})
       when is_list(categories) and categories != [] do
    where(query, [n], n.category in ^categories)
  end

  defp apply_category_filter(query, _), do: query

  defp apply_domain_tag_filter(query, %{"domain_tags" => tags})
       when is_list(tags) and tags != [] do
    where(query, [n], fragment("? && ?", n.domain_tags, ^tags))
  end

  defp apply_domain_tag_filter(query, _), do: query

  defp sanitize_like(str) do
    str
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  defp build_explanation(prompt, count, from_date, to_date) do
    "Found #{count} article(s) matching \"#{String.slice(prompt, 0, 100)}\" " <>
      "for #{Date.to_iso8601(from_date)} to #{Date.to_iso8601(to_date)}"
  end
end
