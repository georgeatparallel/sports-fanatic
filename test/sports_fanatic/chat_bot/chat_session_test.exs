defmodule SportsFanatic.ChatBot.ChatSessionTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.ChatBot.ChatSession

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp valid_user_id, do: Ecto.UUID.generate()

  # ---------------------------------------------------------------------------
  # changeset/2 — required fields
  # ---------------------------------------------------------------------------

  describe "changeset/2 — required fields" do
    test "valid with user_id" do
      changeset = ChatSession.changeset(%ChatSession{}, %{user_id: valid_user_id()})
      assert changeset.valid?
    end

    test "invalid without user_id" do
      changeset = ChatSession.changeset(%ChatSession{}, %{})
      refute changeset.valid?
      assert %{user_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid when user_id is nil" do
      changeset = ChatSession.changeset(%ChatSession{}, %{user_id: nil})
      refute changeset.valid?
      assert %{user_id: ["can't be blank"]} = errors_on(changeset)
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/2 — status validation
  # ---------------------------------------------------------------------------

  describe "changeset/2 — status validation" do
    test "accepts status 'active'" do
      changeset =
        ChatSession.changeset(%ChatSession{}, %{user_id: valid_user_id(), status: "active"})

      assert changeset.valid?
    end

    test "accepts status 'expired'" do
      changeset =
        ChatSession.changeset(%ChatSession{}, %{user_id: valid_user_id(), status: "expired"})

      assert changeset.valid?
    end

    test "rejects an unknown status value" do
      changeset =
        ChatSession.changeset(%ChatSession{}, %{user_id: valid_user_id(), status: "closed"})

      refute changeset.valid?
      assert %{status: _} = errors_on(changeset)
    end

    test "rejects a numeric-looking status string" do
      changeset =
        ChatSession.changeset(%ChatSession{}, %{user_id: valid_user_id(), status: "1"})

      refute changeset.valid?
      assert %{status: _} = errors_on(changeset)
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/2 — optional fields
  # ---------------------------------------------------------------------------

  describe "changeset/2 — optional fields" do
    test "accepts last_activity_at datetime" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      changeset =
        ChatSession.changeset(%ChatSession{}, %{user_id: valid_user_id(), last_activity_at: now})

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :last_activity_at) == now
    end

    test "valid when last_activity_at is omitted" do
      changeset = ChatSession.changeset(%ChatSession{}, %{user_id: valid_user_id()})
      assert changeset.valid?
    end
  end

  # ---------------------------------------------------------------------------
  # Schema defaults
  # ---------------------------------------------------------------------------

  describe "schema defaults" do
    test "default status is 'active'" do
      assert %ChatSession{}.status == "active"
    end
  end
end
