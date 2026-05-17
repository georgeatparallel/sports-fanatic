defmodule SportsFanatic.Predictions.StadiumsTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.Predictions.Stadiums

  # ---------------------------------------------------------------------------
  # coordinates/1
  # ---------------------------------------------------------------------------

  describe "coordinates/1" do
    test "nil venue returns nil" do
      assert Stadiums.coordinates(nil) == nil
    end

    test "unknown venue returns nil" do
      assert Stadiums.coordinates(99_999) == nil
    end

    test "Yankee Stadium (3313) returns correct lat/lon" do
      result = Stadiums.coordinates(3313)
      assert %{lat: lat, lon: lon} = result
      assert_in_delta lat, 40.8297, 0.001
      assert_in_delta lon, -73.9262, 0.001
    end

    test "Coors Field (19) returns correct lat/lon" do
      result = Stadiums.coordinates(19)
      assert %{lat: lat, lon: lon} = result
      assert_in_delta lat, 39.7559, 0.001
      assert_in_delta lon, -104.9942, 0.001
    end

    test "Fenway Park (3) returns correct lat/lon" do
      result = Stadiums.coordinates(3)
      assert %{lat: lat, lon: lon} = result
      assert_in_delta lat, 42.3467, 0.001
      assert_in_delta lon, -71.0972, 0.001
    end

    test "Oracle Park (2395) returns correct lat/lon" do
      result = Stadiums.coordinates(2395)
      assert %{lat: lat, lon: lon} = result
      assert_in_delta lat, 37.7786, 0.001
      assert_in_delta lon, -122.3897, 0.001
    end

    test "Dodger Stadium (22) returns lat in southern California range" do
      result = Stadiums.coordinates(22)
      assert %{lat: lat, lon: lon} = result
      # LA is roughly 34°N, -118°W
      assert lat > 33.0 and lat < 35.0
      assert lon < -117.0 and lon > -120.0
    end

    test "result map contains only lat and lon keys" do
      result = Stadiums.coordinates(3313)
      assert Map.keys(result) |> Enum.sort() == [:lat, :lon]
    end
  end

  # ---------------------------------------------------------------------------
  # all/0
  # ---------------------------------------------------------------------------

  describe "all/0" do
    test "returns a non-empty map" do
      venues = Stadiums.all()
      assert is_map(venues)
      assert map_size(venues) > 20
    end

    test "all values have lat and lon" do
      Stadiums.all()
      |> Map.values()
      |> Enum.each(fn venue ->
        assert Map.has_key?(venue, :lat)
        assert Map.has_key?(venue, :lon)
        assert is_float(venue.lat)
        assert is_float(venue.lon)
      end)
    end

    test "all keys are positive integers" do
      Stadiums.all()
      |> Map.keys()
      |> Enum.each(fn k ->
        assert is_integer(k) and k > 0
      end)
    end

    test "all latitudes are within continental US range" do
      Stadiums.all()
      |> Map.values()
      |> Enum.each(fn venue ->
        # All MLB stadiums are between ~24°N and ~49°N
        assert venue.lat > 24.0 and venue.lat < 50.0
        # All MLB stadiums longitude: ~-124°W to ~-74°W (Rogers Centre ~-79°W)
        assert venue.lon < -70.0 and venue.lon > -125.0
      end)
    end
  end
end
