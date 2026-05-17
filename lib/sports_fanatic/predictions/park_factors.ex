defmodule SportsFanatic.Predictions.ParkFactors do
  @moduledoc """
  Park hit factors by venue_id. Falls back to 1.0 when unknown.

  Defaults are ported from `hit_features.py` DEFAULT_PARK_HIT_FACTORS.
  If a row exists in `mlb.park_hr_factors` with a non-null `hit_factor`,
  that value overrides the default.
  """

  import Ecto.Query

  alias SportsFanatic.Repo

  @defaults %{
    19 => 1.10,
    2602 => 1.06,
    3 => 1.05,
    17 => 1.03,
    5325 => 1.02,
    3313 => 1.02,
    2681 => 1.02,
    2 => 1.01,
    4 => 1.01,
    2392 => 1.01,
    15 => 1.01,
    14 => 1.00,
    22 => 1.00,
    4705 => 1.00,
    32 => 1.00,
    3312 => 0.99,
    5 => 0.99,
    1 => 0.98,
    3309 => 0.98,
    2889 => 0.97,
    3289 => 0.97,
    2394 => 0.96,
    7 => 0.96,
    31 => 0.96,
    680 => 0.95,
    2680 => 0.95,
    12 => 0.95,
    2395 => 0.94,
    4169 => 0.95,
    10 => 0.95
  }

  @spec hit_factor(integer | nil, integer | nil) :: float
  def hit_factor(nil, _), do: 1.0
  def hit_factor(venue_id, nil), do: hit_factor_static(venue_id)

  def hit_factor(venue_id, season) when is_integer(venue_id) do
    case fetch_db_factor(venue_id, season) do
      nil -> Map.get(@defaults, venue_id, 1.0)
      v -> v
    end
  end

  @spec hit_factor_static(integer | nil) :: float
  def hit_factor_static(nil), do: 1.0

  def hit_factor_static(venue_id) when is_integer(venue_id),
    do: Map.get(@defaults, venue_id, 1.0)

  def defaults, do: @defaults

  defp fetch_db_factor(venue_id, season) do
    query =
      from(p in "park_hr_factors",
        prefix: "mlb",
        where: p.venue_id == ^venue_id and p.season == ^season,
        select: p.hit_factor,
        limit: 1
      )

    case Repo.one(query) do
      nil -> nil
      f when is_float(f) -> f
      _ -> nil
    end
  rescue
    _ -> nil
  end
end
