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
end
