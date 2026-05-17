defmodule SportsFanatic.Agents.Actions.FetchPlayerStats do
  @moduledoc """
  Tool action: given a player name (or fuzzy match), returns recent picks +
  basic season info. Used by `XReplyAgent` to assemble factual context.

  Returns an empty map when no match is found — never errors on missing
  data because the reply agent will fall back to a generic reply.
  """

  use SportsFanatic.Agents.Action,
    name: "fetch_player_stats",
    description: "Look up a player's recent picks + basic profile"

  import Ecto.Query

  alias SportsFanatic.Mlb.{Pick, Player}
  alias SportsFanatic.Repo

  @impl true
  def run(%{"player_name" => name}, _ctx) when is_binary(name) do
    case find_player(name) do
      nil ->
        {:ok, %{found: false, player_name: name}}

      %Player{} = player ->
        picks =
          Repo.all(
            from p in Pick,
              where: p.player_id == ^player.id or p.player_mlb_id == ^safe_mlb_id(player),
              order_by: [desc: p.prediction_date],
              limit: 7,
              select: %{
                date: p.prediction_date,
                prediction: p.prediction,
                confidence: p.confidence,
                actual_result: p.actual_result
              }
          )

        {:ok,
         %{
           found: true,
           player_name: player.full_name,
           position: player.position,
           recent_picks: picks
         }}
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

  defp safe_mlb_id(%Player{external_ids: %{"mlb_id" => id}}) when is_integer(id), do: id

  defp safe_mlb_id(%Player{external_ids: %{"mlb_id" => id}}) when is_binary(id) do
    case Integer.parse(id) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp safe_mlb_id(_), do: 0
end
