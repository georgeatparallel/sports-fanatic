defmodule SportsFanatic.FeatureFlags.FeatureFlagTest do
  @moduledoc """
  Unit tests for the FeatureFlag schema changesets.
  These tests do not require a database connection.
  """
  use ExUnit.Case, async: true

  alias SportsFanatic.FeatureFlags.FeatureFlag

  describe "create_changeset/2" do
    test "valid changeset with all fields" do
      changeset =
        FeatureFlag.create_changeset(%FeatureFlag{}, %{
          key: "my_flag",
          enabled: true,
          description: "A test flag"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :key) == "my_flag"
      assert Ecto.Changeset.get_change(changeset, :enabled) == true
      assert Ecto.Changeset.get_change(changeset, :description) == "A test flag"
    end

    test "valid changeset with key only" do
      changeset = FeatureFlag.create_changeset(%FeatureFlag{}, %{key: "simple_flag"})
      assert changeset.valid?
    end

    test "invalid without key" do
      changeset = FeatureFlag.create_changeset(%FeatureFlag{}, %{})
      refute changeset.valid?
      assert %{key: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid with empty key" do
      changeset = FeatureFlag.create_changeset(%FeatureFlag{}, %{key: ""})
      refute changeset.valid?
    end

    test "invalid key with uppercase letters" do
      changeset = FeatureFlag.create_changeset(%FeatureFlag{}, %{key: "MyFlag"})
      refute changeset.valid?
      assert %{key: [_]} = errors_on(changeset)
    end

    test "invalid key with spaces" do
      changeset = FeatureFlag.create_changeset(%FeatureFlag{}, %{key: "my flag"})
      refute changeset.valid?
    end

    test "invalid key with hyphens" do
      changeset = FeatureFlag.create_changeset(%FeatureFlag{}, %{key: "my-flag"})
      refute changeset.valid?
    end

    test "valid key with underscores and numbers" do
      changeset = FeatureFlag.create_changeset(%FeatureFlag{}, %{key: "flag_v2_beta"})
      assert changeset.valid?
    end

    test "key max length is 100" do
      long_key = String.duplicate("a", 101)
      changeset = FeatureFlag.create_changeset(%FeatureFlag{}, %{key: long_key})
      refute changeset.valid?
    end

    test "key at exactly 100 characters is valid" do
      key_100 = String.duplicate("a", 100)
      changeset = FeatureFlag.create_changeset(%FeatureFlag{}, %{key: key_100})
      assert changeset.valid?
    end

    test "enabled defaults to false in schema" do
      flag = %FeatureFlag{}
      assert flag.enabled == false
    end
  end

  describe "update_changeset/2" do
    test "allows updating enabled" do
      flag = %FeatureFlag{key: "test", enabled: false}
      changeset = FeatureFlag.update_changeset(flag, %{enabled: true})
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :enabled) == true
    end

    test "allows updating description" do
      flag = %FeatureFlag{key: "test", description: "old"}
      changeset = FeatureFlag.update_changeset(flag, %{description: "new"})
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :description) == "new"
    end

    test "does not allow updating key" do
      flag = %FeatureFlag{key: "test"}
      changeset = FeatureFlag.update_changeset(flag, %{key: "new_key"})
      assert changeset.valid?
      # key change should be ignored
      refute Ecto.Changeset.get_change(changeset, :key)
    end
  end

  # Helper to extract errors from a changeset
  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
