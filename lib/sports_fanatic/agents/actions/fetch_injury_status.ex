defmodule SportsFanatic.Agents.Actions.FetchInjuryStatus do
  @moduledoc """
  Tool action: returns the latest `content.injury_reports` row for a given
  player by name. Used by `XReplyAgent`.
  """

  use SportsFanatic.Agents.Action,
    name: "fetch_injury_status",
    description: "Look up the latest injury report for a player by name"

  import Ecto.Query

  alias SportsFanatic.Content.InjuryReport
  alias SportsFanatic.Mlb.Player
  alias SportsFanatic.Repo

  @impl true
  def run(%{"player_name" => name}, _ctx) when is_binary(name) do
    case find_player(name) do
      nil ->
        {:ok, %{found: false, player_name: name}}

      %Player{} = player ->
        report =
          Repo.one(
            from ir in InjuryReport,
              where: ir.player_id == ^player.id,
              order_by: [desc: ir.run_date],
              limit: 1
          )

        if report do
          {:ok,
           %{
             found: true,
             player_name: player.full_name,
             current_status: report.current_status,
             tldr: report.tldr,
             expected_return: report.expected_return,
             updated: Date.to_iso8601(report.run_date)
           }}
        else
          {:ok, %{found: true, player_name: player.full_name, current_status: "active"}}
        end
    end
  end

  def run(params, ctx) when is_map(params) do
    string_keyed =
      Map.new(params, fn
        {k, v} when is_atom(k) -> {Atom.to_string(k), v}
        {k, v} -> {k, v}
      end)

    case Map.fetch(string_keyed, "player_name") do
      {:ok, _} -> run(string_keyed, ctx)
      :error -> {:error, :missing_player_name}
    end
  end

  defp find_player(name) do
    Repo.one(
      from p in Player,
        where: fragment("LOWER(?) = LOWER(?)", p.full_name, ^name),
        limit: 1
    )
  rescue
    _ -> nil
  end
end
