defmodule SportsFanatic.Seed do
  @moduledoc """
  Seeds the database with MLB teams, players, today's schedule, lineups, and news.

  Usage from release:
    bin/sports_fanatic eval "SportsFanatic.Seed.run()"
    bin/sports_fanatic eval "SportsFanatic.Seed.run(:teams)"
    bin/sports_fanatic eval "SportsFanatic.Seed.run(:players)"
    bin/sports_fanatic eval "SportsFanatic.Seed.run(:schedule)"
    bin/sports_fanatic eval "SportsFanatic.Seed.run(:lineups)"
    bin/sports_fanatic eval "SportsFanatic.Seed.run(:news)"
  """

  require Logger

  import Ecto.Query

  alias SportsFanatic.Repo
  alias SportsFanatic.Mlb.{Team, Player, ScheduledGame, Lineup}
  alias SportsFanatic.Content.NewsItem
  alias SportsFanatic.PythonBridge
  alias SportsFanatic.ExternalApis.FantasyNerds

  def run(step \\ :all) do
    # Start only what we need — not the full app (which tries to bind port 4000)
    Application.load(:sports_fanatic)
    Application.ensure_all_started(:req)
    Application.ensure_all_started(:postgrex)
    Application.ensure_all_started(:ecto_sql)

    # Start the Repo directly
    case SportsFanatic.Repo.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    case step do
      :all -> run_all()
      :teams -> seed_teams()
      :players -> seed_players()
      :schedule -> seed_schedule()
      :lineups -> seed_lineups()
      :news -> seed_news()
      other -> IO.puts("Unknown step: #{inspect(other)}")
    end
  end

  defp run_all do
    IO.puts("=== Seeding Sports Fanatic Database ===\n")

    IO.puts("Step 1/5: Seeding MLB teams...")
    seed_teams()

    IO.puts("\nStep 2/5: Seeding players from all team rosters...")
    seed_players()

    IO.puts("\nStep 3/5: Seeding today's schedule...")
    seed_schedule()

    IO.puts("\nStep 4/5: Seeding today's lineups...")
    seed_lineups()

    IO.puts("\nStep 5/5: Seeding news...")
    seed_news()

    IO.puts("\n=== Seeding Complete! ===")
    print_stats()
  end

  def seed_teams do
    case PythonBridge.fetch_mlb_teams() do
      {:ok, %{"teams" => teams}} ->
        count =
          Enum.reduce(teams, 0, fn t, acc ->
            league_short =
              cond do
                String.contains?(t["league"] || "", "American") -> "AL"
                String.contains?(t["league"] || "", "National") -> "NL"
                true -> t["league"] || ""
              end

            division_short =
              cond do
                String.contains?(t["division"] || "", "East") -> "East"
                String.contains?(t["division"] || "", "Central") -> "Central"
                String.contains?(t["division"] || "", "West") -> "West"
                true -> t["division"] || ""
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
                IO.puts("  Failed: #{t["name"]}: #{inspect(cs.errors)}")
                acc
            end
          end)

        IO.puts("  Seeded #{count} teams")

      {:error, reason} ->
        IO.puts("  Failed to fetch teams from MLB API: #{inspect(reason)}")
        IO.puts("  Trying FantasyNerds API instead...")
        seed_teams_from_nerds()
    end
  end

  defp seed_teams_from_nerds do
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

            case Repo.insert(Team.changeset(%Team{}, attrs),
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

        IO.puts("  Seeded #{count} teams from FantasyNerds")

      error ->
        IO.puts("  Failed to fetch teams from FantasyNerds: #{inspect(error)}")
    end
  end

  def seed_players do
    teams = Repo.all(from t in Team, where: not is_nil(t.slug))

    if Enum.empty?(teams) do
      IO.puts("  No teams found. Run seed_teams first.")
    else
      total =
        Enum.reduce(teams, 0, fn team, total_acc ->
          mlb_id = get_in(team.external_ids, ["mlb_id"])

          if is_nil(mlb_id) do
            IO.puts("  Skipping #{team.name} (no MLB ID)")
            total_acc
          else
            case PythonBridge.fetch_roster(mlb_id) do
              {:ok, %{"players" => players}} ->
                count =
                  Enum.reduce(players, 0, fn p, acc ->
                    jersey = parse_jersey(p["jersey_number"])

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

                    existing = Repo.get_by(Player, full_name: p["full_name"], team_id: team.id)

                    result =
                      if existing do
                        existing |> Player.changeset(attrs) |> Repo.update()
                      else
                        Repo.insert(Player.changeset(%Player{}, attrs))
                      end

                    case result do
                      {:ok, _} ->
                        acc + 1

                      {:error, cs} ->
                        IO.puts("  Failed: #{p["full_name"]}: #{inspect(cs.errors)}")
                        acc
                    end
                  end)

                IO.puts("  #{team.name}: #{count} players")
                total_acc + count

              {:error, reason} ->
                IO.puts("  Failed roster for #{team.name}: #{inspect(reason)}")
                total_acc
            end
          end
        end)

      IO.puts("  Total: #{total} players seeded")
    end
  end

  def seed_schedule do
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
                IO.puts("  Failed game #{game["game_id"]}: #{inspect(cs.errors)}")
                acc
            end
          end)

        IO.puts("  Seeded #{count} scheduled games for #{today}")

      {:error, reason} ->
        IO.puts("  Failed to fetch schedule: #{inspect(reason)}")
    end
  end

  def seed_lineups do
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

        IO.puts("  Seeded #{count} lineup entries for #{today}")

      {:error, reason} ->
        IO.puts("  Failed to fetch lineups: #{inspect(reason)}")
    end
  end

  def seed_news do
    case FantasyNerds.fetch_news() do
      {:ok, news_list} when is_list(news_list) ->
        count =
          Enum.reduce(news_list, 0, fn item, acc ->
            slug = Slug.slugify(item["title"] || "untitled") |> String.slice(0, 200)
            slug = if slug == "", do: "news-#{System.unique_integer([:positive])}", else: slug

            changeset =
              %NewsItem{}
              |> NewsItem.changeset(%{
                source: "fantasynerds",
                external_id:
                  to_string(item["id"] || item["newsId"] || System.unique_integer([:positive])),
                slug: slug,
                title: item["title"] || "Untitled",
                body: item["body"] || item["analysis"] || item["content"] || "",
                summary: item["summary"],
                published_date: Date.utc_today(),
                category: item["category"] || "general"
              })

            case Repo.insert(changeset,
                   on_conflict: :nothing,
                   conflict_target: [:source, :external_id]
                 ) do
              # conflict, nothing inserted
              {:ok, %{id: nil}} -> acc
              {:ok, _} -> acc + 1
              {:error, _} -> acc
            end
          end)

        IO.puts("  Seeded #{count} news items")

      {:ok, _} ->
        IO.puts("  No news items returned")

      {:error, reason} ->
        IO.puts("  Failed to fetch news: #{inspect(reason)}")
    end
  end

  defp print_stats do
    team_count = Repo.aggregate(Team, :count)
    player_count = Repo.aggregate(Player, :count)
    game_count = Repo.one(from sg in ScheduledGame, select: count())
    lineup_count = Repo.one(from l in Lineup, select: count())
    news_count = Repo.one(from n in NewsItem, select: count())

    IO.puts("""

    Database Stats:
      Teams:           #{team_count}
      Players:         #{player_count}
      Scheduled Games: #{game_count}
      Lineup Entries:  #{lineup_count}
      News Items:      #{news_count}
    """)
  end

  defp parse_date(nil), do: Date.utc_today()

  defp parse_date(str) when is_binary(str) do
    case Date.from_iso8601(str) do
      {:ok, d} -> d
      _ -> Date.utc_today()
    end
  end

  defp parse_date(_), do: Date.utc_today()

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(_), do: nil

  defp parse_jersey(n) when is_integer(n), do: n

  defp parse_jersey(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_jersey(_), do: nil
end
