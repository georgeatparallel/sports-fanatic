defmodule SportsFanatic.ScoutingTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias SportsFanatic.Content.PlayerSourceUrl
  alias SportsFanatic.Scouting.{ScoutingRun, ScoutingRunLog}

  describe "ScoutingRun.changeset/2" do
    test "valid with required fields" do
      changeset = ScoutingRun.changeset(%ScoutingRun{}, %{status: "pending"})
      assert changeset.valid?
    end

    test "valid with all fields" do
      attrs = %{
        status: "running",
        total_players: 100,
        processed_players: 50,
        config: %{"research_concurrency" => 5, "classification_concurrency" => 5},
        started_at: DateTime.utc_now(),
        completed_at: nil,
        error: nil
      }

      changeset = ScoutingRun.changeset(%ScoutingRun{}, attrs)
      assert changeset.valid?
    end

    test "invalid with invalid status" do
      changeset = ScoutingRun.changeset(%ScoutingRun{}, %{status: "invalid_status"})
      refute changeset.valid?
      assert %{status: _} = errors_on(changeset)
    end

    test "valid statuses include all expected values" do
      for status <- ~w(pending running completed failed cancelled) do
        changeset = ScoutingRun.changeset(%ScoutingRun{}, %{status: status})
        assert changeset.valid?, "Expected '#{status}' to be valid"
      end
    end

    test "defaults status to pending" do
      run = %ScoutingRun{}
      assert run.status == "pending"
    end

    test "defaults processed_players to 0" do
      run = %ScoutingRun{}
      assert run.processed_players == 0
    end

    test "defaults config to empty map" do
      run = %ScoutingRun{}
      assert run.config == %{}
    end
  end

  describe "ScoutingRunLog.changeset/2" do
    test "valid with required fields" do
      attrs = %{
        scouting_run_id: Ecto.UUID.generate(),
        player_id: Ecto.UUID.generate(),
        step: "research",
        status: "started"
      }

      changeset = ScoutingRunLog.changeset(%ScoutingRunLog{}, attrs)
      assert changeset.valid?
    end

    test "valid with all fields" do
      attrs = %{
        scouting_run_id: Ecto.UUID.generate(),
        player_id: Ecto.UUID.generate(),
        step: "classify",
        status: "completed",
        message: "Classified 5 URLs",
        metadata: %{"urls_classified" => 5}
      }

      changeset = ScoutingRunLog.changeset(%ScoutingRunLog{}, attrs)
      assert changeset.valid?
    end

    test "invalid without scouting_run_id" do
      attrs = %{player_id: Ecto.UUID.generate(), step: "research", status: "started"}
      changeset = ScoutingRunLog.changeset(%ScoutingRunLog{}, attrs)
      refute changeset.valid?
    end

    test "invalid without player_id" do
      attrs = %{scouting_run_id: Ecto.UUID.generate(), step: "research", status: "started"}
      changeset = ScoutingRunLog.changeset(%ScoutingRunLog{}, attrs)
      refute changeset.valid?
    end

    test "invalid with invalid step" do
      attrs = %{
        scouting_run_id: Ecto.UUID.generate(),
        player_id: Ecto.UUID.generate(),
        step: "invalid_step",
        status: "started"
      }

      changeset = ScoutingRunLog.changeset(%ScoutingRunLog{}, attrs)
      refute changeset.valid?
    end

    test "valid steps include all expected values" do
      for step <- ~w(research classify generate complete error) do
        attrs = %{
          scouting_run_id: Ecto.UUID.generate(),
          player_id: Ecto.UUID.generate(),
          step: step,
          status: "started"
        }

        changeset = ScoutingRunLog.changeset(%ScoutingRunLog{}, attrs)
        assert changeset.valid?, "Expected step '#{step}' to be valid"
      end
    end

    test "valid statuses include all expected values" do
      for status <- ~w(started completed failed skipped) do
        attrs = %{
          scouting_run_id: Ecto.UUID.generate(),
          player_id: Ecto.UUID.generate(),
          step: "research",
          status: status
        }

        changeset = ScoutingRunLog.changeset(%ScoutingRunLog{}, attrs)
        assert changeset.valid?, "Expected status '#{status}' to be valid"
      end
    end

    test "defaults metadata to empty map" do
      log = %ScoutingRunLog{}
      assert log.metadata == %{}
    end
  end

  describe "PlayerSourceUrl.changeset/2" do
    test "valid with required fields" do
      attrs = %{
        player_id: Ecto.UUID.generate(),
        url: "https://example.com/article",
        source_type: "news"
      }

      changeset = PlayerSourceUrl.changeset(%PlayerSourceUrl{}, attrs)
      assert changeset.valid?
    end

    test "valid with all fields" do
      attrs = %{
        player_id: Ecto.UUID.generate(),
        url: "https://example.com/scouting-report",
        source_type: "analyst",
        classification: "performance_analysis",
        content_summary: "Player showed improvement in hitting",
        key_facts: %{"facts" => ["Batting .350 in last 10 games"]},
        processed_at: DateTime.utc_now()
      }

      changeset = PlayerSourceUrl.changeset(%PlayerSourceUrl{}, attrs)
      assert changeset.valid?
    end

    test "invalid without player_id" do
      attrs = %{url: "https://example.com", source_type: "news"}
      changeset = PlayerSourceUrl.changeset(%PlayerSourceUrl{}, attrs)
      refute changeset.valid?
    end

    test "invalid without url" do
      attrs = %{player_id: Ecto.UUID.generate(), source_type: "news"}
      changeset = PlayerSourceUrl.changeset(%PlayerSourceUrl{}, attrs)
      refute changeset.valid?
    end

    test "invalid without source_type" do
      attrs = %{player_id: Ecto.UUID.generate(), url: "https://example.com"}
      changeset = PlayerSourceUrl.changeset(%PlayerSourceUrl{}, attrs)
      refute changeset.valid?
    end

    test "invalid with invalid source_type" do
      attrs = %{
        player_id: Ecto.UUID.generate(),
        url: "https://example.com",
        source_type: "invalid"
      }

      changeset = PlayerSourceUrl.changeset(%PlayerSourceUrl{}, attrs)
      refute changeset.valid?
    end

    test "valid source_types include all expected values" do
      for source_type <- ~w(news analyst fantasy_betting) do
        attrs = %{
          player_id: Ecto.UUID.generate(),
          url: "https://example.com/#{source_type}",
          source_type: source_type
        }

        changeset = PlayerSourceUrl.changeset(%PlayerSourceUrl{}, attrs)
        assert changeset.valid?, "Expected source_type '#{source_type}' to be valid"
      end
    end

    test "valid classifications include all expected values" do
      classifications = ~w(
        performance_analysis injury_report trade_rumor prospect_evaluation
        fantasy_value betting_insight general_news
      )

      for classification <- classifications do
        attrs = %{
          player_id: Ecto.UUID.generate(),
          url: "https://example.com/#{classification}",
          source_type: "news",
          classification: classification
        }

        changeset = PlayerSourceUrl.changeset(%PlayerSourceUrl{}, attrs)
        assert changeset.valid?, "Expected classification '#{classification}' to be valid"
      end
    end

    test "rejects invalid URL scheme" do
      attrs = %{
        player_id: Ecto.UUID.generate(),
        url: "ftp://example.com/file",
        source_type: "news"
      }

      changeset = PlayerSourceUrl.changeset(%PlayerSourceUrl{}, attrs)
      refute changeset.valid?
      assert %{url: ["must be a valid HTTP(S) URL"]} = errors_on(changeset)
    end

    test "rejects URL without host" do
      attrs = %{
        player_id: Ecto.UUID.generate(),
        url: "not-a-url",
        source_type: "news"
      }

      changeset = PlayerSourceUrl.changeset(%PlayerSourceUrl{}, attrs)
      refute changeset.valid?
    end

    test "accepts HTTPS URL" do
      attrs = %{
        player_id: Ecto.UUID.generate(),
        url: "https://espn.com/mlb/player/12345",
        source_type: "analyst"
      }

      changeset = PlayerSourceUrl.changeset(%PlayerSourceUrl{}, attrs)
      assert changeset.valid?
    end
  end

  # Helper
  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
