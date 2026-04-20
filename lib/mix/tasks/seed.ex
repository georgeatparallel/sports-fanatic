defmodule Mix.Tasks.Seed do
  @moduledoc """
  Seeds the database with MLB teams, players, today's schedule, lineups, and news.

  Usage:
    mix seed              # Seed everything
    mix seed teams        # Seed teams only
    mix seed players      # Seed players (requires teams first)
    mix seed schedule     # Seed today's schedule
    mix seed lineups      # Seed today's lineups
    mix seed news         # Seed recent news
  """

  use Mix.Task

  require Logger

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      ["teams"] -> seed_teams()
      ["players"] -> seed_players()
      ["schedule"] -> seed_schedule()
      ["lineups"] -> seed_lineups()
      ["news"] -> seed_news()
      _ -> seed_all()
    end
  end

  defp seed_all do
    Mix.shell().info("=== Seeding Sports Fanatic Database ===\n")

    Mix.shell().info("Step 1/5: Seeding MLB teams...")
    seed_teams()

    Mix.shell().info("\nStep 2/5: Seeding players from all team rosters...")
    seed_players()

    Mix.shell().info("\nStep 3/5: Seeding today's schedule...")
    seed_schedule()

    Mix.shell().info("\nStep 4/5: Seeding today's lineups...")
    seed_lineups()

    Mix.shell().info("\nStep 5/5: Seeding news...")
    seed_news()

    Mix.shell().info("\n=== Seeding Complete! ===")
    print_stats()
  end

  defp seed_teams do
    alias SportsFanatic.Repo
    alias SportsFanatic.Mlb.Team
    alias SportsFanatic.PythonBridge

    case PythonBridge.fetch_mlb_teams() do
      {:ok, %{"teams" => teams}} ->
        count =
          Enum.reduce(teams, 0, fn t, acc ->
            league_short =
              cond do
                String.contains?(t["league"] || "", "American") -> "AL"
                String.contains?(t["league"] || "", "National") -> "NL"
                true -> t["league"]
              end

            division_short =
              cond do
                String.contains?(t["division"] || "", "East") -> "East"
                String.contains?(t["division"] || "", "Central") -> "Central"
                String.contains?(t["division"] || "", "West") -> "West"
                true -> t["division"]
              end

            attrs = %{
              name: t["name"],
              city: t["city"],
              abbreviation: t["abbreviation"],
              league: league_short,
              division: division_short,
              external_ids: %{"mlb_id" => t["mlb_id"]}
            }

            changeset = Team.changeset(%Team{}, attrs)

            case Repo.insert(changeset,
                   on_conflict:
                     {:replace,
                      [
                        :name,
                        :city,
                        :abbreviation,
                        :league,
                        :division,
                        :external_ids,
                        :updated_at
                      ]},
                   conflict_target: :slug
                 ) do
              {:ok, _} ->
                acc + 1

              {:error, cs} ->
                Mix.shell().error("  Failed to insert team #{t["name"]}: #{inspect(cs.errors)}")
                acc
            end
          end)

        Mix.shell().info("  Seeded #{count} teams")

      {:error, reason} ->
        Mix.shell().error("  Failed to fetch teams: #{inspect(reason)}")
        Mix.shell().info("  Trying FantasyNerds API instead...")
        seed_teams_from_nerds()
    end
  end

  defp seed_teams_from_nerds do
    alias SportsFanatic.Repo
    alias SportsFanatic.Mlb.Team
    alias SportsFanatic.ExternalApis.FantasyNerds

    case FantasyNerds.fetch_teams() do
      {:ok, teams} when is_list(teams) ->
        count =
          Enum.reduce(teams, 0, fn t, acc ->
            attrs = %{
              name: t["teamName"] || t["name"],
              city: t["city"] || t["locationName"],
              abbreviation: t["code"] || t["abbreviation"],
              league: t["league"],
              division: t["division"],
              external_ids: %{
                "nerds_id" => t["teamId"] || t["id"],
                "mlb_id" => t["mlbId"]
              }
            }

            changeset = Team.changeset(%Team{}, attrs)

            case Repo.insert(changeset,
                   on_conflict:
                     {:replace,
                      [
                        :name,
                        :city,
                        :abbreviation,
                        :league,
                        :division,
                        :external_ids,
                        :updated_at
                      ]},
                   conflict_target: :slug
                 ) do
              {:ok, _} -> acc + 1
              {:error, _} -> acc
            end
          end)

        Mix.shell().info("  Seeded #{count} teams from FantasyNerds")

      {:ok, _} ->
        Mix.shell().error("  Unexpected teams response format")

      {:error, reason} ->
        Mix.shell().error("  Failed to fetch teams from FantasyNerds: #{inspect(reason)}")
    end
  end

  defp seed_players do
    alias SportsFanatic.Repo
    alias SportsFanatic.Mlb.{Team, Player}
    alias SportsFanatic.PythonBridge
    import Ecto.Query

    teams = Repo.all(from t in Team, where: not is_nil(t.slug))

    if Enum.empty?(teams) do
      Mix.shell().error("  No teams found. Run `mix seed teams` first.")
      return_early()
    end

    total =
      Enum.reduce(teams, 0, fn team, total_acc ->
        mlb_id = get_in(team.external_ids, ["mlb_id"])

        if is_nil(mlb_id) do
          Mix.shell().info("  Skipping #{team.name} (no MLB ID)")
          total_acc
        else
          case PythonBridge.fetch_roster(mlb_id) do
            {:ok, %{"players" => players}} ->
              count =
                Enum.reduce(players, 0, fn p, acc ->
                  jersey =
                    case p["jersey_number"] do
                      n when is_integer(n) ->
                        n

                      s when is_binary(s) ->
                        case Integer.parse(s) do
                          {n, _} -> n
                          :error -> nil
                        end

                      _ ->
                        nil
                    end

                  attrs = %{
                    first_name: p["first_name"],
                    last_name: p["last_name"],
                    full_name: p["full_name"],
                    position: p["position"],
                    status:
                      if(String.contains?(p["status"] || "", "Active"),
                        do: "active",
                        else: "inactive"
                      ),
                    jersey_number: jersey,
                    team_id: team.id,
                    external_ids: %{"mlb_id" => p["mlb_id"]},
                    headshot_url:
                      "https://img.mlbstatic.com/mlb-photos/image/upload/d_people:generic:headshot:67:current.png/w_213,q_auto:best/v1/people/#{p["mlb_id"]}/headshot/67/current"
                  }

                  changeset = Player.changeset(%Player{}, attrs)

                  # Use full_name + team_id as logical unique key
                  existing = Repo.get_by(Player, full_name: p["full_name"], team_id: team.id)

                  result =
                    if existing do
                      existing
                      |> Player.changeset(attrs)
                      |> Repo.update()
                    else
                      Repo.insert(changeset)
                    end

                  case result do
                    {:ok, _} ->
                      acc + 1

                    {:error, cs} ->
                      Mix.shell().error("  Failed: #{p["full_name"]}: #{inspect(cs.errors)}")
                      acc
                  end
                end)

              Mix.shell().info("  #{team.name}: #{count} players")
              total_acc + count

            {:error, reason} ->
              Mix.shell().error("  Failed to fetch roster for #{team.name}: #{inspect(reason)}")
              total_acc
          end
        end
      end)

    Mix.shell().info("  Total: #{total} players seeded")
  end

  defp seed_schedule do
    alias SportsFanatic.Repo
    alias SportsFanatic.Mlb.ScheduledGame
    alias SportsFanatic.PythonBridge

    today = Date.utc_today() |> Date.to_iso8601()

    case PythonBridge.fetch_schedule(today) do
      {:ok, %{"games" => games}} ->
        count =
          Enum.reduce(games, 0, fn game, acc ->
            changeset =
              %ScheduledGame{}
              |> ScheduledGame.changeset(%{
                game_id: game["game_id"],
                game_date: parse_date(game["game_date"]),
                game_datetime: parse_datetime(game["game_datetime"]),
                away_mlb_id: game["away_mlb_id"],
                home_mlb_id: game["home_mlb_id"],
                away_name: game["away_name"],
                home_name: game["home_name"],
                away_probable_pitcher: game["away_probable_pitcher"],
                home_probable_pitcher: game["home_probable_pitcher"],
                venue_id: game["venue_id"],
                venue_name: game["venue_name"],
                status: game["status"] || "scheduled"
              })

            case Repo.insert(changeset, on_conflict: :replace_all, conflict_target: :game_id) do
              {:ok, _} ->
                acc + 1

              {:error, cs} ->
                Mix.shell().error("  Failed game #{game["game_id"]}: #{inspect(cs.errors)}")
                acc
            end
          end)

        Mix.shell().info("  Seeded #{count} scheduled games for #{today}")

      {:error, reason} ->
        Mix.shell().error("  Failed to fetch schedule: #{inspect(reason)}")
    end
  end

  defp seed_lineups do
    alias SportsFanatic.Repo
    alias SportsFanatic.Mlb.Lineup
    alias SportsFanatic.ExternalApis.FantasyNerds

    today = Date.utc_today() |> Date.to_iso8601()

    case FantasyNerds.fetch_lineups(today) do
      {:ok, players} ->
        count =
          Enum.reduce(players, 0, fn player, acc ->
            changeset =
              %Lineup{}
              |> Lineup.changeset(%{
                game_date: Date.utc_today(),
                player_nerds_id: player.player_id,
                team_code: player.team_code,
                batting_order: player[:batting_order],
                position: player[:position],
                confirmed: true
              })

            case Repo.insert(changeset,
                   on_conflict:
                     {:replace, [:team_code, :batting_order, :position, :confirmed, :updated_at]},
                   conflict_target: [:game_date, :player_nerds_id]
                 ) do
              {:ok, _} -> acc + 1
              _ -> acc
            end
          end)

        Mix.shell().info("  Seeded #{count} lineup entries for #{today}")

      {:error, reason} ->
        Mix.shell().error("  Failed to fetch lineups: #{inspect(reason)}")
    end
  end

  defp seed_news do
    # Trigger the existing news worker
    alias SportsFanatic.Workers.FetchNewsWorker

    case FetchNewsWorker.perform(%Oban.Job{args: %{}}) do
      :ok -> Mix.shell().info("  News seeded successfully")
      {:error, reason} -> Mix.shell().error("  Failed to seed news: #{inspect(reason)}")
    end
  end

  defp print_stats do
    alias SportsFanatic.Repo
    import Ecto.Query

    team_count = Repo.aggregate(SportsFanatic.Mlb.Team, :count)
    player_count = Repo.aggregate(SportsFanatic.Mlb.Player, :count)
    game_count = Repo.one(from sg in "scheduled_games", prefix: "mlb", select: count())
    lineup_count = Repo.one(from l in "lineups", prefix: "mlb", select: count())
    news_count = Repo.one(from n in "news_items", prefix: "content", select: count())

    Mix.shell().info("""

    Database Stats:
      Teams:           #{team_count}
      Players:         #{player_count}
      Scheduled Games: #{game_count}
      Lineup Entries:  #{lineup_count}
      News Items:      #{news_count}
    """)
  end

  defp parse_date(nil), do: Date.utc_today()

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, d} -> d
      _ -> Date.utc_today()
    end
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp return_early, do: :ok
end
