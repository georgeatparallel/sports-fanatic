defmodule SportsFanatic.ObanConfigTest do
  @moduledoc """
  Unit tests verifying the Oban configuration in config.exs.
  No database required — reads Application config at test time.
  """
  use ExUnit.Case, async: true

  defp oban_config do
    Application.get_env(:sports_fanatic, Oban)
  end

  defp crontab do
    plugins = oban_config()[:plugins] || []

    Enum.find_value(plugins, [], fn
      {Oban.Plugins.Cron, opts} -> Keyword.get(opts, :crontab, [])
      _ -> nil
    end)
  end

  defp queues do
    oban_config()[:queues] || []
  end

  describe "Oban cron schedule" do
    test "crontab is configured" do
      assert length(crontab()) > 0
    end

    test "FetchNewsWorker runs every 5 minutes" do
      entry =
        Enum.find(crontab(), fn {_cron, worker} ->
          worker == SportsFanatic.Workers.FetchNewsWorker
        end)

      assert entry != nil, "FetchNewsWorker not found in crontab"
      {cron_expr, _} = entry
      assert cron_expr == "*/5 * * * *"
    end

    test "FetchLineupsWorker runs at noon UTC (12:00)" do
      entry =
        Enum.find(crontab(), fn {_cron, worker} ->
          worker == SportsFanatic.Workers.FetchLineupsWorker
        end)

      assert entry != nil, "FetchLineupsWorker not found in crontab"
      {cron_expr, _} = entry
      assert cron_expr == "0 12 * * *"
    end

    test "GeneratePlayerSeoWorker runs at 12:30 UTC (8:30 AM ET)" do
      entry =
        Enum.find(crontab(), fn {_cron, worker} ->
          worker == SportsFanatic.Workers.GeneratePlayerSeoWorker
        end)

      assert entry != nil, "GeneratePlayerSeoWorker not found in crontab"
      {cron_expr, _} = entry
      assert cron_expr == "30 12 * * *"
    end

    test "FetchScheduleWorker is in crontab" do
      workers = Enum.map(crontab(), fn {_, w} -> w end)
      assert SportsFanatic.Workers.FetchScheduleWorker in workers
    end

    test "GenerateScoutingWorker is in crontab" do
      workers = Enum.map(crontab(), fn {_, w} -> w end)
      assert SportsFanatic.Workers.GenerateScoutingWorker in workers
    end

    test "GenerateGameDayWorker is in crontab" do
      workers = Enum.map(crontab(), fn {_, w} -> w end)
      assert SportsFanatic.Workers.GenerateGameDayWorker in workers
    end

    test "GenerateSitemapWorker is in crontab" do
      workers = Enum.map(crontab(), fn {_, w} -> w end)
      assert SportsFanatic.Workers.GenerateSitemapWorker in workers
    end

    test "WarmCacheWorker is in crontab" do
      workers = Enum.map(crontab(), fn {_, w} -> w end)
      assert SportsFanatic.Workers.WarmCacheWorker in workers
    end

    test "CleanupWorker is in crontab" do
      workers = Enum.map(crontab(), fn {_, w} -> w end)
      assert SportsFanatic.Workers.CleanupWorker in workers
    end

    test "GeneratePredictionsWorker is in crontab" do
      workers = Enum.map(crontab(), fn {_, w} -> w end)
      assert SportsFanatic.Workers.GeneratePredictionsWorker in workers
    end
  end

  describe "Oban queues" do
    test "default queue is configured" do
      assert Keyword.has_key?(queues(), :default)
    end

    test "data_fetch queue is configured" do
      assert Keyword.has_key?(queues(), :data_fetch)
    end

    test "content_generation queue is configured" do
      assert Keyword.has_key?(queues(), :content_generation)
    end

    test "cache queue is configured" do
      assert Keyword.has_key?(queues(), :cache)
    end

    test "system queue is configured" do
      assert Keyword.has_key?(queues(), :system)
    end

    test "content_generation queue has concurrency of 3" do
      assert queues()[:content_generation] == 3
    end

    test "data_fetch queue has concurrency of 5" do
      assert queues()[:data_fetch] == 5
    end
  end
end
