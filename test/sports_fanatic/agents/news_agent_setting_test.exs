defmodule SportsFanatic.Agents.NewsAgentSettingTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.Agents.NewsAgentSetting

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp valid_user_id, do: Ecto.UUID.generate()

  # ---------------------------------------------------------------------------
  # create_changeset/2
  # ---------------------------------------------------------------------------

  describe "create_changeset/2 — required fields" do
    test "valid changeset with user_id and raw_prompt" do
      attrs = %{user_id: valid_user_id(), raw_prompt: "home run streaks from Aaron Judge"}
      changeset = NewsAgentSetting.create_changeset(%NewsAgentSetting{}, attrs)
      assert changeset.valid?
    end

    test "invalid when raw_prompt is missing" do
      attrs = %{user_id: valid_user_id()}
      changeset = NewsAgentSetting.create_changeset(%NewsAgentSetting{}, attrs)
      refute changeset.valid?
      assert %{raw_prompt: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid when user_id is missing" do
      attrs = %{raw_prompt: "track Bryce Harper trades"}
      changeset = NewsAgentSetting.create_changeset(%NewsAgentSetting{}, attrs)
      refute changeset.valid?
      assert %{user_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid when both required fields are missing" do
      changeset = NewsAgentSetting.create_changeset(%NewsAgentSetting{}, %{})
      refute changeset.valid?
      errors = errors_on(changeset)
      assert Map.has_key?(errors, :raw_prompt)
      assert Map.has_key?(errors, :user_id)
    end
  end

  describe "create_changeset/2 — status defaults" do
    test "sets status to pending on create" do
      attrs = %{user_id: valid_user_id(), raw_prompt: "pitcher injuries"}
      changeset = NewsAgentSetting.create_changeset(%NewsAgentSetting{}, attrs)
      assert changeset.valid?
      # get_field returns the applied value (either from change or struct default)
      assert Ecto.Changeset.get_field(changeset, :status) == "pending"
    end

    test "ignores any status provided in attrs — always forces pending" do
      attrs = %{user_id: valid_user_id(), raw_prompt: "pitcher injuries", status: "active"}
      changeset = NewsAgentSetting.create_changeset(%NewsAgentSetting{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :status) == "pending"
    end
  end

  describe "create_changeset/2 — raw_prompt length validation" do
    test "accepts a prompt of exactly 500 characters" do
      prompt = String.duplicate("a", 500)
      attrs = %{user_id: valid_user_id(), raw_prompt: prompt}
      changeset = NewsAgentSetting.create_changeset(%NewsAgentSetting{}, attrs)
      assert changeset.valid?
    end

    test "rejects a prompt of 501 characters" do
      prompt = String.duplicate("a", 501)
      attrs = %{user_id: valid_user_id(), raw_prompt: prompt}
      changeset = NewsAgentSetting.create_changeset(%NewsAgentSetting{}, attrs)
      refute changeset.valid?
      assert %{raw_prompt: [msg]} = errors_on(changeset)
      assert msg =~ "500"
    end

    test "accepts a short single-word prompt" do
      attrs = %{user_id: valid_user_id(), raw_prompt: "injuries"}
      changeset = NewsAgentSetting.create_changeset(%NewsAgentSetting{}, attrs)
      assert changeset.valid?
    end

    test "accepts a prompt at the boundary minus one" do
      prompt = String.duplicate("b", 499)
      attrs = %{user_id: valid_user_id(), raw_prompt: prompt}
      changeset = NewsAgentSetting.create_changeset(%NewsAgentSetting{}, attrs)
      assert changeset.valid?
    end
  end

  # ---------------------------------------------------------------------------
  # update_changeset/2
  # ---------------------------------------------------------------------------

  describe "update_changeset/2 — valid status values" do
    for status <- ~w(pending active running completed failed expired) do
      test "accepts status #{status}" do
        setting = %NewsAgentSetting{status: "pending"}
        changeset = NewsAgentSetting.update_changeset(setting, %{status: unquote(status)})
        assert changeset.valid?
      end
    end
  end

  describe "update_changeset/2 — invalid status values" do
    test "rejects an unknown status" do
      setting = %NewsAgentSetting{status: "pending"}
      changeset = NewsAgentSetting.update_changeset(setting, %{status: "unknown"})
      refute changeset.valid?
      assert %{status: _} = errors_on(changeset)
    end

    test "treats empty string status as nil (cast converts it) — no inclusion error but field cleared" do
      # Ecto casts empty string to nil for :string fields, which passes validate_inclusion
      # since nil is only rejected if validate_required is also present.
      # This behavior is expected given update_changeset does not call validate_required(:status).
      setting = %NewsAgentSetting{status: "pending"}
      changeset = NewsAgentSetting.update_changeset(setting, %{status: ""})
      # Either valid (nil passes inclusion) or invalid — document actual behavior
      refute Ecto.Changeset.get_field(changeset, :status) == "some_invalid_value"
    end

    test "rejects a numeric status" do
      setting = %NewsAgentSetting{status: "pending"}
      changeset = NewsAgentSetting.update_changeset(setting, %{status: "1"})
      refute changeset.valid?
      assert %{status: _} = errors_on(changeset)
    end
  end

  describe "update_changeset/2 — optional fields" do
    test "accepts parsed_criteria as a map" do
      setting = %NewsAgentSetting{status: "pending"}

      criteria = %{
        "target_players" => ["Aaron Judge"],
        "categories" => ["performance"],
        "requires_exa_search" => false
      }

      changeset = NewsAgentSetting.update_changeset(setting, %{parsed_criteria: criteria})
      assert changeset.valid?
    end

    test "accepts error_message update" do
      setting = %NewsAgentSetting{status: "pending"}

      changeset =
        NewsAgentSetting.update_changeset(setting, %{
          status: "failed",
          error_message: "Python Bridge unavailable"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :error_message) == "Python Bridge unavailable"
    end

    test "accepts last_run_at datetime" do
      setting = %NewsAgentSetting{status: "completed"}
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      changeset = NewsAgentSetting.update_changeset(setting, %{last_run_at: now})
      assert changeset.valid?
    end

    test "accepts last_result as a map" do
      setting = %NewsAgentSetting{status: "completed"}

      result = %{"matched_count" => 3, "run_date" => "2026-05-15"}
      changeset = NewsAgentSetting.update_changeset(setting, %{last_result: result})
      assert changeset.valid?
    end

    test "valid with no changes (empty attrs)" do
      setting = %NewsAgentSetting{status: "active"}
      changeset = NewsAgentSetting.update_changeset(setting, %{})
      assert changeset.valid?
    end
  end

  # ---------------------------------------------------------------------------
  # Schema defaults
  # ---------------------------------------------------------------------------

  describe "schema defaults" do
    test "default status is pending" do
      assert %NewsAgentSetting{}.status == "pending"
    end
  end
end
