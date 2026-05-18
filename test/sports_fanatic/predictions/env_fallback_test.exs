defmodule SportsFanatic.Predictions.EnvFallbackTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias SportsFanatic.Predictions.EnvFallback

  # ---------------------------------------------------------------------------
  # resolve_open_meteo_api_key/1 with a custom env reader
  #
  # The 1-arity accepts an env-reader function `(String.t() -> String.t() | nil)`
  # so we can test all branches without touching process environment variables.
  # ---------------------------------------------------------------------------

  describe "resolve_open_meteo_api_key/1" do
    test "returns {nil, false} when both env vars are unset" do
      reader = fn
        "OPENMETEO_API_KEY" -> nil
        "OPENMATAO_API_KEY" -> nil
        "OPENMATEO_API_KEY" -> nil
        _ -> nil
      end

      assert {nil, false} == EnvFallback.resolve_open_meteo_api_key(reader)
    end

    test "returns the OPENMETEO_API_KEY value and false when it is set" do
      reader = fn
        "OPENMETEO_API_KEY" -> "primary-key-abc"
        _ -> nil
      end

      {key, warned?} = EnvFallback.resolve_open_meteo_api_key(reader)
      assert key == "primary-key-abc"
      refute warned?
    end

    test "returns {value, true} when only OPENMATEO_API_KEY is set (legacy spelling)" do
      reader = fn
        "OPENMETEO_API_KEY" -> nil
        "OPENMATEO_API_KEY" -> "legacy-key-xyz"
        _ -> nil
      end

      {key, warned?} = EnvFallback.resolve_open_meteo_api_key(reader)
      assert key == "legacy-key-xyz"
      assert warned?
    end

    test "emits a Logger.warning when only OPENMATEO_API_KEY is set" do
      reader = fn
        "OPENMETEO_API_KEY" -> nil
        "OPENMATEO_API_KEY" -> "ShphmmtoZz7uTqyV"
        _ -> nil
      end

      log =
        capture_log(fn ->
          EnvFallback.resolve_open_meteo_api_key(reader)
        end)

      assert log =~ "OPENMATAO_API_KEY is set (deprecated spelling)" or
               log =~ "OPENMATEO_API_KEY is set (deprecated spelling)"
    end

    test "OPENMETEO_API_KEY wins over OPENMATEO_API_KEY when both are set" do
      reader = fn
        "OPENMETEO_API_KEY" -> "primary-wins"
        "OPENMATEO_API_KEY" -> "legacy-loses"
        _ -> nil
      end

      {key, warned?} = EnvFallback.resolve_open_meteo_api_key(reader)
      assert key == "primary-wins"
      refute warned?
    end

    test "no warning is emitted when OPENMETEO_API_KEY wins" do
      reader = fn
        "OPENMETEO_API_KEY" -> "primary"
        "OPENMATEO_API_KEY" -> "legacy"
        _ -> nil
      end

      log =
        capture_log(fn ->
          EnvFallback.resolve_open_meteo_api_key(reader)
        end)

      refute log =~ "deprecated"
    end

    test "no warning is emitted when both vars are unset" do
      reader = fn _ -> nil end

      log =
        capture_log(fn ->
          EnvFallback.resolve_open_meteo_api_key(reader)
        end)

      refute log =~ "deprecated"
    end

    test "returns the legacy value string verbatim (no transformation)" do
      raw_key = "ShphmmtoZz7uTqyV"

      reader = fn
        "OPENMETEO_API_KEY" -> nil
        "OPENMATEO_API_KEY" -> raw_key
        _ -> nil
      end

      {key, _warned?} = EnvFallback.resolve_open_meteo_api_key(reader)
      assert key == raw_key
    end
  end

  # ---------------------------------------------------------------------------
  # resolve_open_meteo_api_key/0 — 0-arity reads actual process environment
  # We only call this in a setup-guarded way to avoid side effects on the
  # process env. The 0-arity delegates to 1-arity with &System.get_env/1.
  # ---------------------------------------------------------------------------

  describe "resolve_open_meteo_api_key/0" do
    setup do
      # Save and clear both vars so the test environment is clean.
      orig_primary = System.get_env("OPENMETEO_API_KEY")
      orig_legacy = System.get_env("OPENMATEO_API_KEY")

      System.delete_env("OPENMETEO_API_KEY")
      System.delete_env("OPENMATAO_API_KEY")
      System.delete_env("OPENMATEO_API_KEY")

      on_exit(fn ->
        if orig_primary, do: System.put_env("OPENMETEO_API_KEY", orig_primary)
        if orig_legacy, do: System.put_env("OPENMATEO_API_KEY", orig_legacy)
      end)

      :ok
    end

    test "returns {nil, false} when both env vars are absent" do
      assert {nil, false} == EnvFallback.resolve_open_meteo_api_key()
    end

    test "returns the OPENMETEO_API_KEY when only primary is set" do
      System.put_env("OPENMETEO_API_KEY", "test-key-123")
      {key, warned?} = EnvFallback.resolve_open_meteo_api_key()
      assert key == "test-key-123"
      refute warned?
    end

    test "returns the legacy key and warns when only OPENMATEO is set" do
      System.put_env("OPENMATEO_API_KEY", "legacy-test-key")

      {key, warned?} =
        capture_log(fn ->
          EnvFallback.resolve_open_meteo_api_key()
        end)
        |> tap(fn _ -> :ok end)
        |> then(fn _ -> EnvFallback.resolve_open_meteo_api_key() end)

      assert key == "legacy-test-key"
      assert warned?
    end
  end
end
