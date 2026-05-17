defmodule SportsFanatic.ExternalApis.OpenMeteoTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.ExternalApis.OpenMeteo

  # Synthetic hourly data covering 2 hours: 18:00 and 19:00 UTC on 2026-05-17
  @hourly %{
    "time" => ["2026-05-17T18:00", "2026-05-17T19:00", "2026-05-17T20:00"],
    "temperature_2m" => [68.0, 70.5, 72.0],
    "wind_speed_10m" => [8.0, 9.5, 10.0],
    "wind_direction_10m" => [270, 275, 280],
    "precipitation" => [0.0, 0.1, 0.2],
    "weathercode" => [3, 61, 63],
    "surface_pressure" => [1013.0, 1012.5, 1012.0]
  }

  # ---------------------------------------------------------------------------
  # extract_at_game_time/2 — pure extraction logic; no HTTP
  # ---------------------------------------------------------------------------

  describe "extract_at_game_time/2" do
    test "extracts correct row when game_dt matches first slot" do
      game_dt = ~U[2026-05-17 18:00:00Z]
      result = OpenMeteo.extract_at_game_time(@hourly, game_dt)

      assert result != nil
      assert result["temperature_2m"] == 68.0
      assert result["wind_speed_10m"] == 8.0
      assert result["wind_direction_10m"] == 270
      assert result["precipitation"] == 0.0
      assert result["weathercode"] == 3
      assert result["surface_pressure"] == 1013.0
    end

    test "extracts correct row when game_dt matches second slot" do
      game_dt = ~U[2026-05-17 19:00:00Z]
      result = OpenMeteo.extract_at_game_time(@hourly, game_dt)

      assert result != nil
      assert result["temperature_2m"] == 70.5
      assert result["wind_speed_10m"] == 9.5
      assert result["precipitation"] == 0.1
      assert result["weathercode"] == 61
    end

    test "extracts correct row when game_dt matches third slot" do
      game_dt = ~U[2026-05-17 20:00:00Z]
      result = OpenMeteo.extract_at_game_time(@hourly, game_dt)

      assert result != nil
      assert result["temperature_2m"] == 72.0
    end

    test "returns nil when game_dt is not in the hourly list" do
      game_dt = ~U[2026-05-17 23:00:00Z]
      result = OpenMeteo.extract_at_game_time(@hourly, game_dt)
      assert result == nil
    end

    test "ignores minutes and seconds — truncates to the hour boundary" do
      # 19:45 should match the 19:00 slot since we truncate to hour
      game_dt = ~U[2026-05-17 19:45:00Z]
      # The function uses format_hour which renders HH:00, so it should NOT match
      # 19:00 unless it does DateTime.truncate(:second) + format_hour which outputs
      # the same string as 19:00. Let's verify the actual behaviour documented in code:
      # format_hour uses Calendar.strftime "%Y-%m-%dT%H:00" which ignores minutes.
      result = OpenMeteo.extract_at_game_time(@hourly, game_dt)
      # 19:45 → formatted as "2026-05-17T19:00" which IS in the list
      assert result != nil
      assert result["temperature_2m"] == 70.5
    end

    test "returns nil for an empty time list" do
      hourly = Map.put(@hourly, "time", [])
      game_dt = ~U[2026-05-17 19:00:00Z]
      result = OpenMeteo.extract_at_game_time(hourly, game_dt)
      assert result == nil
    end

    test "handles missing field keys gracefully (returns nil for that value)" do
      sparse = %{
        "time" => ["2026-05-17T18:00"],
        "temperature_2m" => [68.0]
        # other fields absent
      }

      game_dt = ~U[2026-05-17 18:00:00Z]
      result = OpenMeteo.extract_at_game_time(sparse, game_dt)
      assert result != nil
      assert result["temperature_2m"] == 68.0
      # Missing fields default to nil
      assert result["wind_speed_10m"] == nil
      assert result["precipitation"] == nil
    end

    test "returns nil when called with nil hourly map" do
      game_dt = ~U[2026-05-17 19:00:00Z]
      result = OpenMeteo.extract_at_game_time(nil, game_dt)
      assert result == nil
    end

    test "returns nil when hourly has no time key" do
      hourly = Map.delete(@hourly, "time")
      game_dt = ~U[2026-05-17 19:00:00Z]
      result = OpenMeteo.extract_at_game_time(hourly, game_dt)
      assert result == nil
    end

    test "result map has exactly the 6 expected weather keys" do
      game_dt = ~U[2026-05-17 18:00:00Z]
      result = OpenMeteo.extract_at_game_time(@hourly, game_dt)

      expected_keys =
        ~w(temperature_2m wind_speed_10m wind_direction_10m precipitation weathercode surface_pressure)

      assert Map.keys(result) |> Enum.sort() == Enum.sort(expected_keys)
    end
  end
end
