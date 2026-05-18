defmodule SportsFanatic.DateHelper do
  @moduledoc """
  Date helper that returns "today" in US Eastern time.

  MLB games and content are Eastern-time oriented. Using UTC causes
  the date to flip at 8 PM ET (midnight UTC), showing "tomorrow's"
  empty content instead of today's games.
  """

  @eastern_offset_hours -4

  @doc """
  Returns today's date in US Eastern time.
  During EDT (March-November), Eastern is UTC-4.
  """
  def today do
    DateTime.utc_now()
    |> DateTime.add(@eastern_offset_hours * 3600, :second)
    |> DateTime.to_date()
  end

  @doc """
  Seconds from now until 00:00 Eastern (UTC-4, EDT) of the next calendar day.

  Used to set TTLs for daily page caches so they expire when the ET day rolls
  over. Returns a positive integer, capped at 86_400 (24 h) and floored at 1
  (avoiding SETEX 0 which deletes the key immediately).

  Inherits the existing EDT-only assumption (X-AGENT-001) — no automatic DST
  handling.
  """
  @spec seconds_until_eastern_midnight() :: integer()
  def seconds_until_eastern_midnight do
    now_utc = DateTime.utc_now()
    now_et = DateTime.add(now_utc, @eastern_offset_hours * 3600, :second)

    next_et_midnight =
      now_et
      |> DateTime.to_date()
      |> Date.add(1)
      |> DateTime.new!(~T[00:00:00], "Etc/UTC")

    DateTime.diff(next_et_midnight, now_et, :second)
    |> max(1)
    |> min(86_400)
  end
end
