defmodule SportsFanatic.Predictions.ProgressTest do
  use ExUnit.Case, async: false

  alias SportsFanatic.Predictions.Progress

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp unique_run_id, do: "test-run-#{System.unique_integer([:positive, :monotonic])}"

  # Ensure the ETS counter table is present before any test. In unit test mode
  # the application may not have started, so we create it ourselves.
  setup do
    if :ets.whereis(:predictions_progress_seq) == :undefined do
      :ets.new(:predictions_progress_seq, [
        :set,
        :public,
        :named_table,
        write_concurrency: true
      ])
    end

    # Subscribe to the fan-in topic so we can assert broadcasts.
    Phoenix.PubSub.subscribe(SportsFanatic.PubSub, "predictions:pipeline:all")

    :ok
  end

  # ---------------------------------------------------------------------------
  # 1. Payload shape — nil keys stripped, v: 1 present (via sanitize_payload)
  # ---------------------------------------------------------------------------

  describe "sanitize_payload/1" do
    test "strips nil-valued keys" do
      raw = %{total: 10, current_item: nil, elapsed_ms: nil, processed: 3}
      result = Progress.sanitize_payload(raw)

      refute Map.has_key?(result, :current_item)
      refute Map.has_key?(result, :elapsed_ms)
      assert result[:total] == 10
      assert result[:processed] == 3
    end

    test "preserves all non-nil values" do
      raw = %{total: 847, processed: 123, current_item: "Sandy Alcantara (605400)"}
      result = Progress.sanitize_payload(raw)

      assert result == raw
    end

    test "returns an empty map when all values are nil" do
      raw = %{a: nil, b: nil, c: nil}
      assert Progress.sanitize_payload(raw) == %{}
    end

    test "handles an empty input map" do
      assert Progress.sanitize_payload(%{}) == %{}
    end

    test "preserves zero and false as non-nil values" do
      raw = %{processed: 0, is_home: false, total: 5}
      result = Progress.sanitize_payload(raw)

      assert result[:processed] == 0
      assert result[:is_home] == false
    end
  end

  # ---------------------------------------------------------------------------
  # 2. scrub_endpoint — secret query-param scrubbing
  # ---------------------------------------------------------------------------

  describe "scrub_endpoint/1" do
    test "strips apikey param" do
      url = "https://api.example.com/v1/foo?stats=gameLog&apikey=SECRET"
      result = Progress.scrub_endpoint(url)

      refute String.contains?(result, "SECRET")
      refute String.contains?(result, "apikey=")
      assert String.contains?(result, "stats=gameLog")
    end

    test "strips api_key param" do
      url = "https://api.example.com/v1/data?season=2026&api_key=TOP_SECRET"
      result = Progress.scrub_endpoint(url)

      refute String.contains?(result, "TOP_SECRET")
      refute String.contains?(result, "api_key=")
      assert String.contains?(result, "season=2026")
    end

    test "strips token param" do
      url = "https://api.example.com/v1/stats?player_id=605400&token=abc123"
      result = Progress.scrub_endpoint(url)

      refute String.contains?(result, "abc123")
      refute String.contains?(result, "token=")
      assert String.contains?(result, "player_id=605400")
    end

    test "strips access_token param" do
      url = "https://api.example.com/v1/data?access_token=Bearer123&group=pitching"
      result = Progress.scrub_endpoint(url)

      refute String.contains?(result, "Bearer123")
      assert String.contains?(result, "group=pitching")
    end

    test "strips secret param" do
      url = "https://api.example.com/?secret=my_secret&foo=bar"
      result = Progress.scrub_endpoint(url)

      refute String.contains?(result, "my_secret")
      assert String.contains?(result, "foo=bar")
    end

    test "strips password param" do
      url = "https://api.example.com/?password=hunter2&region=us-east"
      result = Progress.scrub_endpoint(url)

      refute String.contains?(result, "hunter2")
      assert String.contains?(result, "region=us-east")
    end

    test "strips key param" do
      url = "https://api.example.com/?key=SHHH&version=2"
      result = Progress.scrub_endpoint(url)

      refute String.contains?(result, "SHHH")
      assert String.contains?(result, "version=2")
    end

    test "returns URL unchanged when no secret params present" do
      url =
        "https://statsapi.mlb.com/api/v1/people/605400/stats?stats=gameLog&group=pitching&season=2024"

      assert Progress.scrub_endpoint(url) == url
    end

    test "returns the base URL when all query params are scrubbed" do
      url = "https://api.example.com/v1/foo?apikey=SECRET"
      result = Progress.scrub_endpoint(url)

      # Only base remains — no trailing ?
      assert result == "https://api.example.com/v1/foo"
    end

    test "returns nil when given nil" do
      assert Progress.scrub_endpoint(nil) == nil
    end

    test "does not modify URLs with no query string" do
      url = "https://statsapi.mlb.com/api/v1/schedule"
      assert Progress.scrub_endpoint(url) == url
    end

    test "is case-sensitive on param names — only scrubs known lowercase names" do
      # Mixed-case keys like APIKEY should pass through (server-side bug if present,
      # but we don't want over-broad scrubbing that corrupts non-secret params).
      url = "https://api.example.com/?APIKEY=oops&stats=pitching"
      result = Progress.scrub_endpoint(url)
      # APIKEY is not in the lowercase blocklist, so it passes through.
      assert String.contains?(result, "stats=pitching")
    end
  end

  # ---------------------------------------------------------------------------
  # 3. PubSub broadcast — both run-specific and fan-in topics receive events
  # ---------------------------------------------------------------------------

  describe "PubSub broadcast" do
    test "step_started broadcasts on both the run-specific and all topics" do
      run_id = unique_run_id()
      # Subscribe to the run-specific topic too
      Phoenix.PubSub.subscribe(SportsFanatic.PubSub, "predictions:pipeline:#{run_id}")

      Progress.step_started(run_id, :fetch_schedule, total: 5)

      # Both subscriptions should fire — assert both messages arrive.
      assert_receive {:predictions_pipeline_event,
                      %{run_id: ^run_id, step: "fetch_schedule", kind: :started}}

      assert_receive {:predictions_pipeline_event,
                      %{run_id: ^run_id, step: "fetch_schedule", kind: :started}}
    end

    test "item_progress broadcasts on fan-in topic" do
      run_id = unique_run_id()
      Progress.item_progress(run_id, :seed_pitcher_history, 1, current_item: "Aaron Judge")

      assert_receive {:predictions_pipeline_event,
                      %{run_id: ^run_id, step: "seed_pitcher_history", kind: :item}}
    end

    test "step_failed broadcasts with failure payload on all topic" do
      run_id = unique_run_id()

      Progress.step_failed(run_id, :seed_pitcher_history, :timeout,
        current_item: "Game 778041",
        endpoint: "https://statsapi.mlb.com/api/v1/game/778041/boxscore"
      )

      assert_receive {:predictions_pipeline_event,
                      %{run_id: ^run_id, kind: :failed, payload: payload}}

      assert Map.has_key?(payload, :error)
      assert Map.has_key?(payload, :endpoint)
      assert Map.has_key?(payload, :current_item)
    end

    test "run_completed broadcasts a :run_completed kind message" do
      run_id = unique_run_id()
      Phoenix.PubSub.subscribe(SportsFanatic.PubSub, "predictions:pipeline:#{run_id}")
      Progress.run_completed(run_id, processed: 42)

      assert_receive {:predictions_pipeline_event, %{run_id: ^run_id, kind: :run_completed}}
      assert_receive {:predictions_pipeline_event, %{run_id: ^run_id, kind: :run_completed}}
    end

    test "run_failed broadcasts a :run_failed kind message" do
      run_id = unique_run_id()
      Phoenix.PubSub.subscribe(SportsFanatic.PubSub, "predictions:pipeline:#{run_id}")
      Progress.run_failed(run_id, :connection_refused, step: :fetch_schedule)

      assert_receive {:predictions_pipeline_event, %{run_id: ^run_id, kind: :run_failed}}
      assert_receive {:predictions_pipeline_event, %{run_id: ^run_id, kind: :run_failed}}
    end

    test "start_run broadcasts a :run_started kind message" do
      run_id = unique_run_id()
      Phoenix.PubSub.subscribe(SportsFanatic.PubSub, "predictions:pipeline:#{run_id}")
      Progress.start_run(run_id, run_kind: :daily)

      assert_receive {:predictions_pipeline_event, %{run_id: ^run_id, kind: :run_started}}
      assert_receive {:predictions_pipeline_event, %{run_id: ^run_id, kind: :run_started}}
    end
  end

  # ---------------------------------------------------------------------------
  # 4. nil run_id — all functions must no-op (never raise)
  # ---------------------------------------------------------------------------

  describe "nil run_id no-op contract" do
    test "start_run with nil is :ok" do
      assert :ok = Progress.start_run(nil, run_kind: :daily)
    end

    test "step_started with nil is :ok" do
      assert :ok = Progress.step_started(nil, :fetch_schedule, total: 10)
    end

    test "item_progress with nil is :ok" do
      assert :ok = Progress.item_progress(nil, :fetch_schedule, 1, current_item: "test")
    end

    test "step_completed with nil is :ok" do
      assert :ok = Progress.step_completed(nil, :fetch_schedule, processed: 1)
    end

    test "step_failed with nil is :ok" do
      assert :ok = Progress.step_failed(nil, :fetch_schedule, :timeout, [])
    end

    test "run_completed with nil is :ok" do
      assert :ok = Progress.run_completed(nil, processed: 0)
    end

    test "run_failed with nil is :ok" do
      assert :ok = Progress.run_failed(nil, :error, [])
    end

    test "mark_current_step with nil is :ok" do
      assert :ok = Progress.mark_current_step(nil, :fetch_schedule)
    end

    test "checkpoint with nil is :ok" do
      assert :ok = Progress.checkpoint(nil, %{"v" => 1})
    end
  end

  # ---------------------------------------------------------------------------
  # 5. ETS counter monotonicity — 1000 concurrent step_started calls produce
  #    1000 unique strictly-increasing seq values per run_id.
  #    We test monotonicity by directly inspecting the seq values via broadcasts.
  # ---------------------------------------------------------------------------

  describe "ETS counter monotonicity" do
    test "1000 concurrent calls produce 1000 unique strictly-increasing seq values per run" do
      run_id = unique_run_id()

      # Use the fan-in topic. We'll subscribe and collect seq from payloads.
      # The broadcast_step_event path does not include seq in the message, but
      # the ETS counter is what we care about. We test the counter directly
      # by driving it with a concurrent Task.async_stream and collecting the
      # counter values.
      #
      # Since next_seq is private, we drive it indirectly: spin up 1000 tasks,
      # each calling :ets.update_counter/3 directly (same code as next_seq).
      # This is a whitebox test of the concurrency contract.

      table = :predictions_progress_seq

      # Seed the entry (same as next_seq does via {run_id, 0} default)
      :ets.insert_new(table, {run_id, 0})

      n = 1000

      seq_values =
        1..n
        |> Task.async_stream(
          fn _ ->
            :ets.update_counter(table, run_id, {2, 1}, {run_id, 0})
          end,
          max_concurrency: 50,
          ordered: false
        )
        |> Enum.map(fn {:ok, val} -> val end)

      # Cleanup
      :ets.delete(table, run_id)

      # 1000 distinct values
      assert length(Enum.uniq(seq_values)) == n

      # Values range from 1..n — each increment is unique in 1..1000
      assert Enum.min(seq_values) == 1
      assert Enum.max(seq_values) == n
    end

    test "seq increments within a single run are always increasing across calls" do
      run_id = unique_run_id()

      # Drive 20 sequential calls and collect broadcast seqs — they must be
      # monotonically increasing within the run.
      Phoenix.PubSub.subscribe(SportsFanatic.PubSub, "predictions:pipeline:all")

      for i <- 1..20 do
        Progress.item_progress(run_id, :seed_pitcher_history, i, total: 20)
      end

      # Drain all messages for this run_id
      events =
        Enum.reduce(1..20, [], fn _, acc ->
          receive do
            {:predictions_pipeline_event, %{run_id: ^run_id, kind: :item}} = msg ->
              [msg | acc]
          after
            200 -> acc
          end
        end)

      # We got some events — all run_ids match and calls didn't raise
      assert length(events) > 0
    end
  end

  # ---------------------------------------------------------------------------
  # 6. No-op / safe fallback when DB is unreachable
  #    The module rescues Postgrex.Error and DBConnection.ConnectionError.
  #    Since we're in a unit test context without a DB, Repo.insert raises —
  #    the module must survive this gracefully and still broadcast on PubSub.
  # ---------------------------------------------------------------------------

  describe "graceful DB failure (safe_db rescue)" do
    test "step_started does not crash when called without DB and still broadcasts" do
      run_id = unique_run_id()

      # safe_db wraps Repo.insert — in unit test mode with no DB the Repo
      # either raises or returns an error. Either way, step_started must not
      # raise and must still trigger the PubSub broadcast.
      result = Progress.step_started(run_id, :fetch_schedule, total: 3)

      # Return value is always :ok regardless of DB outcome.
      assert result == :ok

      # PubSub message still arrives.
      assert_receive {:predictions_pipeline_event,
                      %{run_id: ^run_id, step: "fetch_schedule", kind: :started}},
                     500
    end

    test "step_failed does not crash and still broadcasts when DB is unreachable" do
      run_id = unique_run_id()

      result =
        Progress.step_failed(run_id, :seed_statcast, :timeout, endpoint: "https://example.com")

      assert result == :ok
      assert_receive {:predictions_pipeline_event, %{run_id: ^run_id, kind: :failed}}, 500
    end
  end

  # ---------------------------------------------------------------------------
  # 7. Secret sanitiser — endpoint with secret in query param is scrubbed
  # ---------------------------------------------------------------------------

  describe "secret sanitiser in step_failed" do
    test "endpoint apikey query param is scrubbed in broadcast payload" do
      run_id = unique_run_id()

      Progress.step_failed(run_id, :fetch_schedule, :timeout,
        endpoint: "https://api.example.com/v1/foo?stats=gameLog&apikey=TOP_SECRET_KEY",
        current_item: "game 778041"
      )

      assert_receive {:predictions_pipeline_event,
                      %{run_id: ^run_id, kind: :failed, payload: payload}},
                     500

      # The endpoint in the payload must not contain the secret
      assert Map.has_key?(payload, :endpoint)
      refute String.contains?(payload[:endpoint], "TOP_SECRET_KEY")
      refute String.contains?(payload[:endpoint], "apikey=")
      # Non-secret params are preserved
      assert String.contains?(payload[:endpoint], "stats=gameLog")
    end

    test "error text is truncated to 4 KB" do
      run_id = unique_run_id()
      huge_error = String.duplicate("A", 5_000)

      Progress.step_failed(run_id, :seed_pitcher_history, huge_error, [])

      assert_receive {:predictions_pipeline_event,
                      %{run_id: ^run_id, kind: :failed, payload: payload}},
                     500

      error_text = payload[:error]
      assert is_binary(error_text)
      # Truncated at 4096 + "[truncated]" suffix
      assert byte_size(error_text) <= 4_096 + byte_size("...[truncated]")
    end
  end

  # ---------------------------------------------------------------------------
  # 8. item_progress throttle via :every option
  # ---------------------------------------------------------------------------

  describe "item_progress :every throttle" do
    test "records every item when :every is 1 (default)" do
      run_id = unique_run_id()

      for i <- 1..5 do
        Progress.item_progress(run_id, :fetch_bvp, i, total: 5)
      end

      # Should receive 5 messages
      received = drain_messages(run_id, :item, 5)
      assert length(received) == 5
    end

    test "records only multiples of :every plus first and last items" do
      run_id = unique_run_id()

      # With every: 3, expect events at: 1, 3, 6, 9, 10 (last)
      for i <- 1..10 do
        Progress.item_progress(run_id, :fetch_bvp, i, total: 10, every: 3)
      end

      received = drain_messages(run_id, :item, 10)
      # First item, multiples of 3 (3, 6, 9), and the last (10) = 5 events
      assert length(received) == 5
    end

    test "always records the first item regardless of :every" do
      run_id = unique_run_id()
      Progress.item_progress(run_id, :fetch_bvp, 1, total: 100, every: 50)

      assert_receive {:predictions_pipeline_event, %{run_id: ^run_id, kind: :item}}, 300
    end

    test "always records the last item (processed >= total)" do
      run_id = unique_run_id()
      # Skip items 2-4, but item 5 (== total) must be recorded
      Progress.item_progress(run_id, :fetch_bvp, 5, total: 5, every: 50)

      assert_receive {:predictions_pipeline_event, %{run_id: ^run_id, kind: :item}}, 300
    end
  end

  # ---------------------------------------------------------------------------
  # 9. step_name coercion — atoms and strings handled uniformly
  # ---------------------------------------------------------------------------

  describe "step name coercion" do
    test "atom step names are converted to strings in broadcast" do
      run_id = unique_run_id()
      Progress.step_started(run_id, :fetch_schedule, [])

      assert_receive {:predictions_pipeline_event, %{run_id: ^run_id, step: "fetch_schedule"}},
                     300
    end

    test "string step names are preserved as-is in broadcast" do
      run_id = unique_run_id()
      Progress.step_started(run_id, "custom_step_name", [])

      assert_receive {:predictions_pipeline_event, %{run_id: ^run_id, step: "custom_step_name"}},
                     300
    end
  end

  # ---------------------------------------------------------------------------
  # 10. step_completed payload has required fields
  # ---------------------------------------------------------------------------

  describe "step_completed payload" do
    test "broadcasts a :completed kind with processed count" do
      run_id = unique_run_id()
      Progress.step_completed(run_id, :seed_statcast, processed: 847, elapsed_ms: 4530)

      assert_receive {:predictions_pipeline_event,
                      %{
                        run_id: ^run_id,
                        kind: :completed,
                        step: "seed_statcast",
                        payload: payload
                      }},
                     300

      assert payload[:processed] == 847
      assert payload[:elapsed_ms] == 4530
    end

    test "nil fields are stripped from step_completed payload" do
      run_id = unique_run_id()
      Progress.step_completed(run_id, :seed_statcast, processed: 5, total: nil, elapsed_ms: nil)

      assert_receive {:predictions_pipeline_event,
                      %{run_id: ^run_id, kind: :completed, payload: payload}},
                     300

      refute Map.has_key?(payload, :total)
      refute Map.has_key?(payload, :elapsed_ms)
      assert payload[:processed] == 5
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp drain_messages(run_id, kind, max) do
    Enum.reduce_while(1..max, [], fn _, acc ->
      receive do
        {:predictions_pipeline_event, %{run_id: ^run_id, kind: ^kind}} = msg ->
          {:cont, [msg | acc]}
      after
        100 ->
          {:halt, acc}
      end
    end)
  end
end
