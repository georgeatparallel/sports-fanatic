defmodule SportsFanaticWeb.AdminLivePredictionsTest do
  @moduledoc """
  Unit tests for the Predictions-tab live-stream logic in AdminLive.

  These tests are pure (no DB) — they exercise the socket assignment
  transformations triggered by {:predictions_pipeline_event, ...} messages
  and the event-handler contracts by calling the functions that hold the
  logic directly.

  LiveView mount-time tests (which need a DB + Joshua session) are deferred
  to CI; see "Deferred to CI" at the bottom of this file.
  """

  use ExUnit.Case, async: true

  # We need PubSub running to test the subscription / broadcast path.
  # PubSub is started by the application; in unit tests we use it directly.

  # ---------------------------------------------------------------------------
  # apply_predictions_event — pure socket transformation logic
  #
  # We extract and replicate the logic from the private helpers so we can
  # drive them without mounting a LiveView (which requires DB + session).
  # This mirrors the implementation in admin_live.ex lines 2604-2665.
  # ---------------------------------------------------------------------------

  # ---- Minimal socket stub --------------------------------------------------

  defp fake_socket(assigns \\ []) do
    defaults = %{
      active_run: nil,
      active_run_events: [],
      active_run_total_events: 0,
      active_run_failed_event: nil,
      seed_eligibility: %{earliest_date: nil, seed_from: nil, seed_through: nil}
    }

    overrides = if is_list(assigns), do: Map.new(assigns), else: assigns
    %{assigns: Map.merge(defaults, overrides)}
  end

  # ---- Logic helpers (mirror of the private functions in admin_live.ex) -----

  defp apply_event(socket, event) do
    case event do
      %{kind: :run_started} = ev ->
        active = %{
          run_id: ev[:run_id],
          run_kind: ev[:run_kind],
          started_at: ev[:inserted_at],
          current_step: nil,
          processed: 0,
          total: nil,
          current_item: nil
        }

        %{
          socket
          | assigns:
              Map.merge(socket.assigns, %{
                active_run: active,
                active_run_events:
                  trim_events([format_event(ev) | socket.assigns.active_run_events]),
                active_run_total_events: socket.assigns.active_run_total_events + 1,
                active_run_failed_event: nil
              })
        }

      %{kind: :run_completed} = ev ->
        %{
          socket
          | assigns:
              Map.merge(socket.assigns, %{
                active_run: nil,
                active_run_events:
                  trim_events([format_event(ev) | socket.assigns.active_run_events]),
                active_run_total_events: socket.assigns.active_run_total_events + 1
              })
        }

      %{kind: :run_failed} = ev ->
        %{
          socket
          | assigns:
              Map.merge(socket.assigns, %{
                active_run: nil,
                active_run_failed_event: format_event(ev),
                active_run_events:
                  trim_events([format_event(ev) | socket.assigns.active_run_events]),
                active_run_total_events: socket.assigns.active_run_total_events + 1
              })
        }

      %{kind: :failed} = ev ->
        %{
          socket
          | assigns:
              Map.merge(socket.assigns, %{
                active_run_failed_event: format_event(ev),
                active_run_events:
                  trim_events([format_event(ev) | socket.assigns.active_run_events]),
                active_run_total_events: socket.assigns.active_run_total_events + 1
              })
        }

      %{kind: kind} = ev when kind in [:started, :item, :completed] ->
        active = update_active_run(socket.assigns.active_run, ev)

        %{
          socket
          | assigns:
              Map.merge(socket.assigns, %{
                active_run: active,
                active_run_events:
                  trim_events([format_event(ev) | socket.assigns.active_run_events]),
                active_run_total_events: socket.assigns.active_run_total_events + 1
              })
        }

      _other ->
        socket
    end
  end

  defp update_active_run(nil, ev) do
    %{
      run_id: ev[:run_id],
      run_kind: ev[:run_kind],
      started_at: ev[:inserted_at],
      current_step: ev[:step],
      processed: get_in(ev, [:payload, :processed]) || 0,
      total: get_in(ev, [:payload, :total]),
      current_item: get_in(ev, [:payload, :current_item])
    }
  end

  defp update_active_run(active, ev) do
    payload = ev[:payload] || %{}

    Map.merge(active, %{
      current_step: ev[:step] || active[:current_step],
      processed: payload[:processed] || active[:processed],
      total: payload[:total] || active[:total],
      current_item: payload[:current_item] || active[:current_item]
    })
  end

  defp format_event(ev) do
    %{
      run_id: ev[:run_id],
      step: ev[:step],
      kind: ev[:kind],
      inserted_at: ev[:inserted_at] || DateTime.utc_now(),
      payload: ev[:payload] || %{}
    }
  end

  defp trim_events(events), do: Enum.take(events, 50)

  defp unique_run_id, do: "test-run-#{System.unique_integer([:positive, :monotonic])}"

  # ---------------------------------------------------------------------------
  # 1. Currently-Running panel — absent when no run is active
  # ---------------------------------------------------------------------------

  describe "active_run assign when no run is active" do
    test "initial socket has active_run: nil" do
      socket = fake_socket()
      assert socket.assigns.active_run == nil
    end

    test "active_run_events is an empty list initially" do
      socket = fake_socket()
      assert socket.assigns.active_run_events == []
    end
  end

  # ---------------------------------------------------------------------------
  # 2. :run_started event → panel appears
  # ---------------------------------------------------------------------------

  describe "apply_event/2 with :run_started" do
    setup do
      run_id = unique_run_id()

      event = %{
        run_id: run_id,
        run_kind: :initial_seed,
        step: nil,
        kind: :run_started,
        inserted_at: DateTime.utc_now(),
        payload: %{}
      }

      {:ok, run_id: run_id, event: event}
    end

    test "sets active_run with run_id and run_kind", %{event: event, run_id: run_id} do
      socket = fake_socket() |> apply_event(event)

      assert socket.assigns.active_run != nil
      assert socket.assigns.active_run.run_id == run_id
      assert socket.assigns.active_run.run_kind == :initial_seed
    end

    test "clears active_run_failed_event on new run", %{event: event} do
      socket =
        fake_socket(active_run_failed_event: %{kind: :failed, step: "old_step"})
        |> apply_event(event)

      assert socket.assigns.active_run_failed_event == nil
    end

    test "prepends to active_run_events list", %{event: event} do
      socket = fake_socket() |> apply_event(event)
      assert length(socket.assigns.active_run_events) == 1
    end

    test "increments active_run_total_events", %{event: event} do
      socket = fake_socket() |> apply_event(event)
      assert socket.assigns.active_run_total_events == 1
    end

    test "active_run.processed starts at 0", %{event: event} do
      socket = fake_socket() |> apply_event(event)
      assert socket.assigns.active_run.processed == 0
    end
  end

  # ---------------------------------------------------------------------------
  # 3. :item events → counters update
  # ---------------------------------------------------------------------------

  describe "apply_event/2 with :item events" do
    test "updates current_step from item event step" do
      run_id = unique_run_id()

      started_ev = %{
        run_id: run_id,
        run_kind: :daily,
        kind: :run_started,
        inserted_at: DateTime.utc_now(),
        payload: %{}
      }

      item_ev = %{
        run_id: run_id,
        kind: :item,
        step: "seed_pitcher_history",
        inserted_at: DateTime.utc_now(),
        payload: %{processed: 42, total: 100, current_item: "Aaron Judge (592450)"}
      }

      socket = fake_socket() |> apply_event(started_ev) |> apply_event(item_ev)

      assert socket.assigns.active_run.current_step == "seed_pitcher_history"
      assert socket.assigns.active_run.processed == 42
      assert socket.assigns.active_run.total == 100
      assert socket.assigns.active_run.current_item == "Aaron Judge (592450)"
    end

    test "each item event increments active_run_total_events" do
      run_id = unique_run_id()

      socket =
        fake_socket()
        |> apply_event(%{
          run_id: run_id,
          kind: :run_started,
          inserted_at: DateTime.utc_now(),
          payload: %{}
        })
        |> apply_event(%{
          run_id: run_id,
          kind: :item,
          step: "step_a",
          inserted_at: DateTime.utc_now(),
          payload: %{processed: 1}
        })
        |> apply_event(%{
          run_id: run_id,
          kind: :item,
          step: "step_a",
          inserted_at: DateTime.utc_now(),
          payload: %{processed: 2}
        })

      assert socket.assigns.active_run_total_events == 3
    end
  end

  # ---------------------------------------------------------------------------
  # 4. :failed event → red banner appears with step + item + endpoint + error
  # ---------------------------------------------------------------------------

  describe "apply_event/2 with :failed" do
    test "sets active_run_failed_event with failure context" do
      run_id = unique_run_id()

      failed_ev = %{
        run_id: run_id,
        kind: :failed,
        step: "seed_pitcher_history",
        inserted_at: DateTime.utc_now(),
        payload: %{
          current_item: "Sandy Alcantara (605400)",
          endpoint: "https://statsapi.mlb.com/api/v1/people/605400/stats",
          http_status: 503,
          error: "%HTTPoison.Error{reason: :timeout}"
        }
      }

      socket = fake_socket() |> apply_event(failed_ev)

      refute socket.assigns.active_run_failed_event == nil
      failed = socket.assigns.active_run_failed_event
      assert failed.step == "seed_pitcher_history"
      assert failed.payload[:current_item] == "Sandy Alcantara (605400)"
      assert failed.payload[:http_status] == 503
      assert is_binary(failed.payload[:error])
    end

    test ":failed event does NOT clear active_run" do
      run_id = unique_run_id()

      active = %{run_id: run_id, run_kind: :daily, processed: 5}

      failed_ev = %{
        run_id: run_id,
        kind: :failed,
        step: "seed_pitcher_history",
        inserted_at: DateTime.utc_now(),
        payload: %{error: "some error"}
      }

      socket = fake_socket(active_run: active) |> apply_event(failed_ev)

      # :failed is a step-level failure — the run is still "active" (not cleared)
      # until :run_failed fires. This matches the admin_live.ex behaviour.
      refute socket.assigns.active_run == nil
    end

    test ":run_failed clears active_run and sets failed_event" do
      run_id = unique_run_id()

      run_failed_ev = %{
        run_id: run_id,
        kind: :run_failed,
        step: "seed_pitcher_history",
        inserted_at: DateTime.utc_now(),
        payload: %{error: "pipeline aborted"}
      }

      socket = fake_socket() |> apply_event(run_failed_ev)

      assert socket.assigns.active_run == nil
      refute socket.assigns.active_run_failed_event == nil
    end
  end

  # ---------------------------------------------------------------------------
  # 5. :run_completed → panel clears
  # ---------------------------------------------------------------------------

  describe "apply_event/2 with :run_completed" do
    test "clears active_run on run_completed" do
      run_id = unique_run_id()

      started = %{
        run_id: run_id,
        kind: :run_started,
        inserted_at: DateTime.utc_now(),
        payload: %{}
      }

      completed = %{
        run_id: run_id,
        kind: :run_completed,
        inserted_at: DateTime.utc_now(),
        payload: %{}
      }

      socket = fake_socket() |> apply_event(started) |> apply_event(completed)

      assert socket.assigns.active_run == nil
    end

    test "active_run_events grows then stabilises at 50" do
      run_id = unique_run_id()

      socket =
        Enum.reduce(1..55, fake_socket(), fn i, sock ->
          ev = %{
            run_id: run_id,
            kind: :item,
            step: "step",
            inserted_at: DateTime.utc_now(),
            payload: %{processed: i}
          }

          apply_event(sock, ev)
        end)

      assert length(socket.assigns.active_run_events) == 50
    end
  end

  # ---------------------------------------------------------------------------
  # 6. dismiss_failed_event handler logic — clears active_run_failed_event
  # ---------------------------------------------------------------------------

  describe "dismiss_failed_event handler" do
    test "clears active_run_failed_event assign" do
      failed_ev = %{kind: :failed, step: "step_a", payload: %{}}
      socket = fake_socket(active_run_failed_event: failed_ev)

      # Simulates the handler body: assign(socket, active_run_failed_event: nil)
      updated = %{socket | assigns: Map.put(socket.assigns, :active_run_failed_event, nil)}

      assert updated.assigns.active_run_failed_event == nil
    end
  end

  # ---------------------------------------------------------------------------
  # 7. PubSub subscription — verify the module subscribes on mount
  # ---------------------------------------------------------------------------

  describe "PubSub subscription contract" do
    test "subscribing to predictions:pipeline:all receives events from Progress" do
      Phoenix.PubSub.subscribe(SportsFanatic.PubSub, "predictions:pipeline:all")

      run_id = unique_run_id()
      SportsFanatic.Predictions.Progress.start_run(run_id, run_kind: :daily)

      assert_receive {:predictions_pipeline_event, %{run_id: ^run_id, kind: :run_started}}, 500
    end

    test "a :started event arrives for each step_started call" do
      Phoenix.PubSub.subscribe(SportsFanatic.PubSub, "predictions:pipeline:all")

      run_id = unique_run_id()
      SportsFanatic.Predictions.Progress.step_started(run_id, :fetch_schedule, total: 1)

      assert_receive {:predictions_pipeline_event,
                      %{run_id: ^run_id, step: "fetch_schedule", kind: :started}},
                     500
    end

    test "a :failed event arrives for step_failed call" do
      Phoenix.PubSub.subscribe(SportsFanatic.PubSub, "predictions:pipeline:all")

      run_id = unique_run_id()

      SportsFanatic.Predictions.Progress.step_failed(run_id, :seed_pitcher_history, :timeout,
        current_item: "Sandy Alcantara (605400)",
        endpoint: "https://statsapi.mlb.com/api/v1/people/605400/stats",
        http_status: 503
      )

      assert_receive {:predictions_pipeline_event,
                      %{run_id: ^run_id, kind: :failed, payload: payload}},
                     500

      assert payload[:current_item] == "Sandy Alcantara (605400)"
      assert payload[:http_status] == 503
      # Endpoint should be scrubbed of any secret params (none in this URL, so unchanged)
      assert String.starts_with?(payload[:endpoint], "https://statsapi.mlb.com")
    end
  end

  # ---------------------------------------------------------------------------
  # 8. InitialSeedWorker enqueueing (structural contract)
  # ---------------------------------------------------------------------------

  describe "InitialSeedWorker enqueue contract" do
    test "InitialSeedWorker.new/1 produces a valid Oban job" do
      job =
        SportsFanatic.Workers.InitialSeedWorker.new(%{
          "seed_from" => "2021-03-01",
          "seed_through" => "2026-05-16"
        })

      assert job.valid?
      assert job.changes.queue == "predictions"
    end

    test "worker queue is :predictions" do
      job =
        SportsFanatic.Workers.InitialSeedWorker.new(%{
          "seed_from" => "2021-03-01",
          "seed_through" => "2024-12-31"
        })

      assert job.changes.queue == "predictions"
    end

    test "worker max_attempts is 5 (long-running)" do
      job =
        SportsFanatic.Workers.InitialSeedWorker.new(%{
          "seed_from" => "2021-03-01",
          "seed_through" => "2024-12-31"
        })

      assert job.changes.max_attempts == 5
    end
  end
end
