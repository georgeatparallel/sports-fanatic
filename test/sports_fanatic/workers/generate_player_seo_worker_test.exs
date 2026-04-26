defmodule SportsFanatic.Workers.GeneratePlayerSeoWorkerTest do
  use SportsFanatic.DataCase, async: true
  use Oban.Testing, repo: SportsFanatic.Repo

  alias SportsFanatic.Workers.GeneratePlayerSeoWorker
  alias SportsFanatic.Mlb.{Player, Team}

  # --- Helpers ---

  defp create_team(attrs \\ %{}) do
    defaults = %{
      name: "Test Team #{System.unique_integer([:positive])}",
      city: "Test City",
      slug: "test-team-#{System.unique_integer([:positive])}"
    }

    Repo.insert!(Team.changeset(%Team{}, Map.merge(defaults, attrs)))
  end

  defp create_player(team, attrs \\ %{}) do
    defaults = %{
      full_name: "Test Player #{System.unique_integer([:positive])}",
      slug: "test-player-#{System.unique_integer([:positive])}",
      status: "active",
      team_id: team.id
    }

    Repo.insert!(Player.changeset(%Player{}, Map.merge(defaults, attrs)))
  end

  describe "Oban.Worker behavior" do
    test "worker is a valid Oban.Worker" do
      assert function_exported?(GeneratePlayerSeoWorker, :perform, 1)
    end

    test "worker can be enqueued" do
      assert {:ok, _job} = Oban.insert(GeneratePlayerSeoWorker.new(%{}))
    end

    test "worker uses content_generation queue" do
      job = GeneratePlayerSeoWorker.new(%{})
      assert job.changes.queue == "content_generation"
    end

    test "worker has max_attempts of 2" do
      job = GeneratePlayerSeoWorker.new(%{})
      assert job.changes.max_attempts == 2
    end
  end

  describe "perform/1 — bio generation" do
    test "generates bio for active player without bio" do
      team = create_team(%{name: "New York Yankees"})

      player =
        create_player(team, %{
          full_name: "Aaron Judge",
          position: "OF",
          bio: nil
        })

      assert :ok = perform_job(GeneratePlayerSeoWorker, %{})

      updated = Repo.get!(Player, player.id)
      assert updated.bio =~ "Aaron Judge"
      assert updated.bio =~ "outfielder"
      assert updated.bio =~ "New York Yankees"
    end

    test "generates bio referencing team name" do
      team = create_team(%{name: "Boston Red Sox"})
      player = create_player(team, %{full_name: "Rafael Devers", position: "3B", bio: nil})

      assert :ok = perform_job(GeneratePlayerSeoWorker, %{})

      updated = Repo.get!(Player, player.id)
      assert updated.bio =~ "Boston Red Sox"
    end

    test "does not overwrite existing bio" do
      team = create_team(%{name: "Cubs"})

      player =
        create_player(team, %{
          full_name: "Dansby Swanson",
          position: "SS",
          bio: "Custom bio already set."
        })

      assert :ok = perform_job(GeneratePlayerSeoWorker, %{})

      updated = Repo.get!(Player, player.id)
      assert updated.bio == "Custom bio already set."
    end

    test "skips inactive players" do
      team = create_team(%{name: "Padres"})

      player =
        create_player(team, %{
          full_name: "Inactive Guy",
          position: "C",
          bio: nil,
          status: "inactive"
        })

      assert :ok = perform_job(GeneratePlayerSeoWorker, %{})

      updated = Repo.get!(Player, player.id)
      assert is_nil(updated.bio) or updated.bio == ""
    end

    test "includes bats and throws in bio when available" do
      team = create_team(%{name: "Dodgers"})

      player =
        create_player(team, %{
          full_name: "Freddie Freeman",
          position: "1B",
          bats: "L",
          throws: "R",
          bio: nil
        })

      assert :ok = perform_job(GeneratePlayerSeoWorker, %{})

      updated = Repo.get!(Player, player.id)
      assert updated.bio =~ "l"
      assert updated.bio =~ "r"
    end

    test "handles player with no position gracefully" do
      team = create_team(%{name: "Mets"})
      player = create_player(team, %{full_name: "Mystery Man", position: nil, bio: nil})

      assert :ok = perform_job(GeneratePlayerSeoWorker, %{})

      updated = Repo.get!(Player, player.id)
      assert is_binary(updated.bio)
      assert updated.bio =~ "Mystery Man"
      assert updated.bio =~ "player"
    end
  end
end
