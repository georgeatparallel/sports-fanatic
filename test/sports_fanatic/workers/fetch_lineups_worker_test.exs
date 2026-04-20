defmodule SportsFanatic.Workers.FetchLineupsWorkerTest do
  use SportsFanatic.DataCase, async: true
  use Oban.Testing, repo: SportsFanatic.Repo

  alias SportsFanatic.Workers.FetchLineupsWorker
  alias SportsFanatic.Mlb.Lineup

  # We use Mox or simple override techniques. Since the project doesn't have
  # Mox configured, we test what we can without mocking external HTTP calls.
  # Workers that call external APIs are tested for job structure and
  # Oban integration concerns.

  describe "Oban.Worker behavior" do
    test "worker is a valid Oban.Worker" do
      assert function_exported?(FetchLineupsWorker, :perform, 1)
    end

    test "worker can be enqueued" do
      assert {:ok, _job} = Oban.insert(FetchLineupsWorker.new(%{}))
    end

    test "worker has correct queue" do
      job = FetchLineupsWorker.new(%{})
      assert job.changes.queue == "data_fetch"
    end

    test "worker has max_attempts of 3" do
      job = FetchLineupsWorker.new(%{})
      assert job.changes.max_attempts == 3
    end
  end

  describe "Lineup.changeset/2" do
    test "valid with game_date and player_nerds_id" do
      attrs = %{
        game_date: Date.utc_today(),
        player_nerds_id: 12345,
        team_code: "NYY",
        batting_order: 1,
        position: "CF",
        confirmed: true
      }

      changeset = Lineup.changeset(%Lineup{}, attrs)
      assert changeset.valid?
    end

    test "invalid without game_date" do
      attrs = %{player_nerds_id: 12345}
      changeset = Lineup.changeset(%Lineup{}, attrs)
      refute changeset.valid?
      assert %{game_date: _} = errors_on(changeset)
    end

    test "invalid without player_nerds_id" do
      attrs = %{game_date: Date.utc_today()}
      changeset = Lineup.changeset(%Lineup{}, attrs)
      refute changeset.valid?
      assert %{player_nerds_id: _} = errors_on(changeset)
    end

    test "defaults confirmed to false" do
      lineup = %Lineup{}
      assert lineup.confirmed == false
    end
  end
end
