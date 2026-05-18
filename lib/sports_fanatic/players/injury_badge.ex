defmodule SportsFanatic.Players.InjuryBadge do
  @moduledoc """
  Pure mapping from scouting/injury source fields to a card-badge atom.

  ## Precedence

  1. Latest `content.scouting_reports.injury_risk` for the player (when the
     value is not `nil`, `""`, or `"unknown"`).
  2. Latest `content.injury_reports.current_status` for the player.
  3. Default: `:grey` (no badge rendered on the card).

  Inputs are accepted case-insensitively and matched after normalisation
  (lower-case, leading/trailing whitespace stripped, hyphens preserved).

  ## Mapping table

  ### `scouting_reports.injury_risk`

  | Value | Badge |
  |-------|-------|
  | `"healthy"`, `"low"` | `:green` |
  | `"day-to-day"`, `"day_to_day"`, `"questionable"`, `"moderate"` | `:yellow` |
  | `"injured"`, `"il"`, `"out"`, `"high"`, `"severe"` | `:red` |
  | `"unknown"`, `nil`, `""`, anything else | fall through to step 2 |

  ### `injury_reports.current_status` (enum in `InjuryReport`)

  | Value | Badge |
  |-------|-------|
  | `"active"`, `"cleared"` | `:green` |
  | `"day-to-day"`, `"recovering"` | `:yellow` |
  | starts with `"injured-list"` (`injured-list-10`, `-15`, `-60`) | `:red` |
  | `"unknown"`, no row, anything else | `:grey` |

  ## Badge-to-CSS mapping (rendered by `CoreComponents.player_card/1`)

  | Badge | Tailwind class | ARIA label |
  |-------|---------------|------------|
  | `:green` | `bg-green-500` | "Healthy" |
  | `:yellow` | `bg-yellow-400` | "Day-to-day" |
  | `:red` | `bg-red-500` | "Injured / IL" |
  | `:grey` / `nil` | *(no dot rendered)* | *(none)* |
  """

  @type badge :: :green | :yellow | :red | :grey

  @doc """
  Resolves the badge atom for a player.

  ## Inputs

    * `scouting_risk` — `t:String.t/0 | nil`, the latest
      `content.scouting_reports.injury_risk` value for the player.
    * `injury_status` — `t:String.t/0 | nil`, the latest
      `content.injury_reports.current_status` value for the player.

  ## Returns

    * `:green | :yellow | :red | :grey`
  """
  @spec for_scouting_or_injury(String.t() | nil, String.t() | nil) :: badge()
  def for_scouting_or_injury(scouting_risk, injury_status) do
    case scouting_badge(scouting_risk) do
      :grey -> injury_badge(injury_status)
      badge -> badge
    end
  end

  defp scouting_badge(nil), do: :grey

  defp scouting_badge(risk) when is_binary(risk) do
    case normalize(risk) do
      "" -> :grey
      "unknown" -> :grey
      "healthy" -> :green
      "low" -> :green
      "day-to-day" -> :yellow
      "day_to_day" -> :yellow
      "questionable" -> :yellow
      "moderate" -> :yellow
      "injured" -> :red
      "il" -> :red
      "out" -> :red
      "high" -> :red
      "severe" -> :red
      _ -> :grey
    end
  end

  defp scouting_badge(_), do: :grey

  defp injury_badge(nil), do: :grey

  defp injury_badge(status) when is_binary(status) do
    case normalize(status) do
      "active" -> :green
      "cleared" -> :green
      "day-to-day" -> :yellow
      "recovering" -> :yellow
      "unknown" -> :grey
      "" -> :grey
      other -> if String.starts_with?(other, "injured-list"), do: :red, else: :grey
    end
  end

  defp injury_badge(_), do: :grey

  defp normalize(s) do
    s
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end
end
