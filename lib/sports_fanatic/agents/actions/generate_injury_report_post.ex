defmodule SportsFanatic.Agents.Actions.GenerateInjuryReportPost do
  @moduledoc """
  Generates the daily "injury report" tweet pair. Pulls the 3-5 most
  newsworthy injury status changes from the last 24 hours via
  `SportsFanatic.X.InjuryReport.recent_status_changes/1` and asks the Python
  Bridge to compose the prose.

  URL goes in the self-reply only.
  """

  use SportsFanatic.Agents.Action,
    name: "generate_injury_report_post",
    description: "Compose the daily injury report X post (main + self-reply)"

  require Logger

  alias SportsFanatic.PythonBridge
  alias SportsFanatic.X.InjuryReport

  @link_url "https://sportsfanatic.com/mlb/injury-report"

  @impl true
  def run(_params, _context) do
    changes = InjuryReport.recent_status_changes(24)

    payload_changes =
      Enum.map(changes, fn c ->
        %{
          player_id: c.player_id,
          category: c.category,
          to_status: c.to_status,
          injury_area: c.injury_area,
          summary: c.summary || ""
        }
      end)

    context = %{
      injury_changes: payload_changes,
      generated_at_iso: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    case PythonBridge.draft_x_post("injury", context, @link_url) do
      {:ok, %{} = body} ->
        {:ok,
         %{
           main_body: Map.get(body, "main_body", ""),
           reply_body: Map.get(body, "reply_body", @link_url),
           link_url: @link_url,
           context: context,
           model: Map.get(body, "model"),
           input_tokens: Map.get(body, "input_tokens", 0),
           output_tokens: Map.get(body, "output_tokens", 0)
         }}

      {:error, reason} = err ->
        Logger.warning("GenerateInjuryReportPost failed: #{inspect(reason)}")
        err
    end
  end
end
