defmodule SportsFanatic.Agents.Actions.GenerateTopHitsPost do
  @moduledoc """
  Generates today's "top hits" tweet pair: a no-URL main body listing the
  top 5 hit predictions and a self-reply that carries the URL to the public
  players index.

  Reads `mlb.picks` for today (ET), filters `prediction == "hit"`, sorts by
  `confidence` descending, takes the top 5. Calls the Python Bridge to
  draft the prose body.
  """

  use SportsFanatic.Agents.Action,
    name: "generate_top_hits_post",
    description: "Compose the daily top-5 hit predictions X post (main + self-reply)"

  import Ecto.Query
  require Logger

  alias SportsFanatic.DateHelper
  alias SportsFanatic.Mlb.Pick
  alias SportsFanatic.PythonBridge
  alias SportsFanatic.Repo

  @link_url "https://sportsfanatic.com/mlb/players"

  @impl true
  def run(_params, _context) do
    today_et = DateHelper.today()

    picks =
      Repo.all(
        from p in Pick,
          where: p.prediction_date == ^today_et,
          where: p.prediction == "hit",
          order_by: [desc: p.confidence],
          limit: 5,
          select: %{
            player_name: p.player_name,
            team: p.player_team,
            confidence: p.confidence,
            vs_team: p.vs_team,
            probable_pitcher: p.probable_pitcher_name
          }
      )

    context = %{
      top_hits: Enum.map(picks, &normalize_pick/1),
      generated_at_iso: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    case PythonBridge.draft_x_post("top_hits", context, @link_url) do
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
        Logger.warning("GenerateTopHitsPost failed: #{inspect(reason)}")
        err
    end
  end

  defp normalize_pick(p) do
    confidence_pct = round((p.confidence || 0.0) * 100)

    %{
      player_name: p.player_name || "",
      team: p.team || "",
      confidence: confidence_pct,
      vs_team: p.vs_team || "",
      vs_pitcher: p.probable_pitcher || ""
    }
  end
end
