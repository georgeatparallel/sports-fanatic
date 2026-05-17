defmodule SportsFanatic.Predictions.Stadiums do
  @moduledoc """
  Static venue → coordinates lookup used as a fallback when the venue is
  not yet in the database. Ported from sports-fan-agent `lib/stadiums.py`.
  """

  @venues %{
    2529 => %{name: "Sutter Health Park", lat: 38.5758, lon: -121.4789},
    31 => %{name: "PNC Park", lat: 40.4471, lon: -80.0064},
    2680 => %{name: "Petco Park", lat: 32.7075, lon: -117.1575},
    680 => %{name: "T-Mobile Park", lat: 47.5915, lon: -122.3329},
    2395 => %{name: "Oracle Park", lat: 37.7786, lon: -122.3897},
    2889 => %{name: "Busch Stadium", lat: 38.6228, lon: -90.1933},
    2523 => %{name: "George M. Steinbrenner Field", lat: 27.9748, lon: -82.5040},
    5325 => %{name: "Globe Life Field", lat: 32.7508, lon: -97.0763},
    14 => %{name: "Rogers Centre", lat: 43.6414, lon: -79.3892},
    3312 => %{name: "Target Field", lat: 44.9821, lon: -93.2784},
    2681 => %{name: "Citizens Bank Park", lat: 39.9035, lon: -75.1598},
    4705 => %{name: "Truist Park", lat: 33.8908, lon: -84.4682},
    4 => %{name: "Guaranteed Rate Field", lat: 41.8300, lon: -87.6346},
    4169 => %{name: "loanDepot park", lat: 25.7781, lon: -80.2197},
    3313 => %{name: "Yankee Stadium", lat: 40.8297, lon: -73.9262},
    32 => %{name: "American Family Field", lat: 43.0280, lon: -87.9712},
    1 => %{name: "Angel Stadium", lat: 33.8003, lon: -117.8827},
    15 => %{name: "Chase Field", lat: 33.4458, lon: -112.0667},
    2 => %{name: "Oriole Park at Camden Yards", lat: 39.2839, lon: -76.6217},
    3 => %{name: "Fenway Park", lat: 42.3467, lon: -71.0972},
    17 => %{name: "Wrigley Field", lat: 41.9484, lon: -87.6553},
    2602 => %{name: "Great American Ball Park", lat: 39.0978, lon: -84.5079},
    5 => %{name: "Progressive Field", lat: 41.4962, lon: -81.6852},
    19 => %{name: "Coors Field", lat: 39.7559, lon: -104.9942},
    2394 => %{name: "Comerica Park", lat: 42.3390, lon: -83.0485},
    2392 => %{name: "Daikin Park", lat: 29.7573, lon: -95.3555},
    7 => %{name: "Kauffman Stadium", lat: 39.0516, lon: -94.4803},
    22 => %{name: "Dodger Stadium", lat: 34.0739, lon: -118.2400},
    3309 => %{name: "Nationals Park", lat: 38.8730, lon: -77.0074},
    3289 => %{name: "Citi Field", lat: 40.7571, lon: -73.8458},
    12 => %{name: "Tropicana Field", lat: 27.7683, lon: -82.6534},
    10 => %{name: "Oakland Coliseum", lat: 37.7516, lon: -122.2005}
  }

  @doc "Return %{lat: ..., lon: ...} or nil if unknown."
  @spec coordinates(integer | nil) :: %{lat: float, lon: float} | nil
  def coordinates(nil), do: nil

  def coordinates(venue_id) when is_integer(venue_id) do
    case Map.get(@venues, venue_id) do
      nil -> nil
      v -> %{lat: v.lat, lon: v.lon}
    end
  end

  def all, do: @venues
end
