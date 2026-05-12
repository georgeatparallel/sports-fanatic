defmodule SportsFanatic.Workers.GenerateGameDayWorker do
  @moduledoc "Generates Game Day Magazines for all scheduled games."

  use Oban.Worker,
    queue: :content_generation,
    max_attempts: 3,
    unique: [period: 3600]

  import Ecto.Query
  alias SportsFanatic.Content.GameDayMagazine
  alias SportsFanatic.Mlb.{ScheduledGame, Team}
  alias SportsFanatic.PythonBridge
  alias SportsFanatic.Repo
  alias SportsFanatic.Workers.WarmCacheWorker

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    today = SportsFanatic.DateHelper.today()

    games =
      ScheduledGame
      |> where([sg], sg.game_date == ^today)
      |> Repo.all()

    Logger.info("Generating Game Day Magazines for #{length(games)} games")

    Enum.each(games, fn game ->
      generate_magazine(game, today)
    end)

    # Trigger cache warming
    %{}
    |> WarmCacheWorker.new()
    |> Oban.insert()

    :ok
  end

  defp generate_magazine(game, date) do
    away_team = get_team_by_mlb_id(game.away_mlb_id)
    home_team = get_team_by_mlb_id(game.home_mlb_id)

    if away_team && home_team do
      slug = "#{away_team.slug}-vs-#{home_team.slug}"
      maybe_generate_magazine(game, date, away_team, home_team, slug)
    end
  end

  defp maybe_generate_magazine(game, date, away_team, home_team, slug) do
    existing =
      GameDayMagazine
      |> where([m], m.game_date == ^date and m.slug == ^slug)
      |> Repo.one()

    if is_nil(existing) do
      do_generate_magazine(game, date, away_team, home_team, slug)
    end
  end

  defp do_generate_magazine(game, date, away_team, home_team, slug) do
    start_ms = System.monotonic_time(:millisecond)
    game_data = build_game_data(game, away_team, home_team)

    case PythonBridge.generate_game_day(game_data) do
      {:ok, %{"magazine" => mag}} ->
        elapsed = System.monotonic_time(:millisecond) - start_ms
        save_magazine(game, date, away_team, home_team, slug, mag, elapsed)

      {:error, reason} ->
        Logger.warning("Game Day generation failed for #{slug}: #{inspect(reason)}")
    end
  end

  defp build_game_data(game, away_team, home_team) do
    %{
      game: %{
        away: %{name: game.away_name, slug: away_team.slug},
        home: %{name: game.home_name, slug: home_team.slug},
        pitchers: %{
          away: game.away_probable_pitcher,
          home: game.home_probable_pitcher
        },
        venue: game.venue_name,
        datetime: game.game_datetime
      }
    }
  end

  defp save_magazine(game, date, away_team, home_team, slug, mag, elapsed) do
    %GameDayMagazine{}
    |> GameDayMagazine.changeset(%{
      game_date: date,
      away_team_id: away_team.id,
      home_team_id: home_team.id,
      game_id: game.game_id,
      slug: slug,
      headline: mag["headline"] || "#{game.away_name} vs #{game.home_name}",
      subheadline: mag["subheadline"],
      matchup_analysis: mag["matchup_analysis"] || "Analysis pending",
      weather_impact: mag["weather_impact"],
      away_lineup: mag["away_lineup"] || %{},
      home_lineup: mag["home_lineup"] || %{},
      away_pitcher: mag["away_pitcher"] || %{name: game.away_probable_pitcher},
      home_pitcher: mag["home_pitcher"] || %{name: game.home_probable_pitcher},
      batter_matchups: mag["batter_matchups"],
      key_storylines: mag["key_storylines"] || [],
      historical_data: mag["historical_data"],
      prediction: mag["prediction"],
      status: "published",
      model_version: "claude-sonnet-4-20250514",
      generation_ms: elapsed,
      published_at: DateTime.utc_now()
    })
    |> Repo.insert()
  end

  defp get_team_by_mlb_id(nil), do: nil

  defp get_team_by_mlb_id(mlb_id) do
    Team
    |> where([t], fragment("(? ->> 'mlb_id')::int = ?", t.external_ids, ^mlb_id))
    |> Repo.one()
  end
end
