defmodule SportsFanatic.ChatBot.ChatMessageTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.ChatBot.ChatMessage

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp valid_session_id, do: Ecto.UUID.generate()

  defp valid_attrs do
    %{
      session_id: valid_session_id(),
      role: "user",
      content: "Who hit the most home runs last week?"
    }
  end

  # ---------------------------------------------------------------------------
  # changeset/2 — required fields
  # ---------------------------------------------------------------------------

  describe "changeset/2 — required fields" do
    test "valid with session_id, role, and content" do
      changeset = ChatMessage.changeset(%ChatMessage{}, valid_attrs())
      assert changeset.valid?
    end

    test "invalid without content" do
      attrs = Map.delete(valid_attrs(), :content)
      changeset = ChatMessage.changeset(%ChatMessage{}, attrs)
      refute changeset.valid?
      assert %{content: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without session_id" do
      attrs = Map.delete(valid_attrs(), :session_id)
      changeset = ChatMessage.changeset(%ChatMessage{}, attrs)
      refute changeset.valid?
      assert %{session_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without role" do
      attrs = Map.delete(valid_attrs(), :role)
      changeset = ChatMessage.changeset(%ChatMessage{}, attrs)
      refute changeset.valid?
      assert %{role: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid when all required fields are missing" do
      changeset = ChatMessage.changeset(%ChatMessage{}, %{})
      refute changeset.valid?
      errors = errors_on(changeset)
      assert Map.has_key?(errors, :session_id)
      assert Map.has_key?(errors, :role)
      assert Map.has_key?(errors, :content)
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/2 — role validation
  # ---------------------------------------------------------------------------

  describe "changeset/2 — role validation" do
    for role <- ~w(user assistant progress) do
      test "accepts role '#{role}'" do
        attrs = Map.put(valid_attrs(), :role, unquote(role))
        changeset = ChatMessage.changeset(%ChatMessage{}, attrs)
        assert changeset.valid?
      end
    end

    test "rejects an unknown role" do
      attrs = Map.put(valid_attrs(), :role, "system")
      changeset = ChatMessage.changeset(%ChatMessage{}, attrs)
      refute changeset.valid?
      assert %{role: _} = errors_on(changeset)
    end

    test "rejects an empty string role" do
      attrs = Map.put(valid_attrs(), :role, "")
      changeset = ChatMessage.changeset(%ChatMessage{}, attrs)
      refute changeset.valid?
    end

    test "rejects role 'admin'" do
      attrs = Map.put(valid_attrs(), :role, "admin")
      changeset = ChatMessage.changeset(%ChatMessage{}, attrs)
      refute changeset.valid?
      assert %{role: _} = errors_on(changeset)
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/2 — content length validation
  # ---------------------------------------------------------------------------

  describe "changeset/2 — content length validation" do
    test "accepts content of exactly 1 character" do
      attrs = Map.put(valid_attrs(), :content, "x")
      changeset = ChatMessage.changeset(%ChatMessage{}, attrs)
      assert changeset.valid?
    end

    test "accepts content of exactly 10,000 characters" do
      attrs = Map.put(valid_attrs(), :content, String.duplicate("a", 10_000))
      changeset = ChatMessage.changeset(%ChatMessage{}, attrs)
      assert changeset.valid?
    end

    test "rejects content of 10,001 characters" do
      attrs = Map.put(valid_attrs(), :content, String.duplicate("a", 10_001))
      changeset = ChatMessage.changeset(%ChatMessage{}, attrs)
      refute changeset.valid?
      assert %{content: [msg]} = errors_on(changeset)
      assert msg =~ "10000"
    end

    test "rejects empty string content" do
      attrs = Map.put(valid_attrs(), :content, "")
      changeset = ChatMessage.changeset(%ChatMessage{}, attrs)
      refute changeset.valid?
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/2 — optional fields
  # ---------------------------------------------------------------------------

  describe "changeset/2 — optional fields" do
    test "accepts metadata as a map" do
      attrs = Map.put(valid_attrs(), :metadata, %{"source" => "exa", "confidence" => 0.9})
      changeset = ChatMessage.changeset(%ChatMessage{}, attrs)
      assert changeset.valid?
    end

    test "accepts news_item_ids as a list of UUIDs" do
      ids = [Ecto.UUID.generate(), Ecto.UUID.generate()]
      attrs = Map.put(valid_attrs(), :news_item_ids, ids)
      changeset = ChatMessage.changeset(%ChatMessage{}, attrs)
      assert changeset.valid?
    end

    test "accepts empty news_item_ids list" do
      attrs = Map.put(valid_attrs(), :news_item_ids, [])
      changeset = ChatMessage.changeset(%ChatMessage{}, attrs)
      assert changeset.valid?
    end
  end

  # ---------------------------------------------------------------------------
  # Schema defaults
  # ---------------------------------------------------------------------------

  describe "schema defaults" do
    test "metadata defaults to empty map" do
      assert %ChatMessage{}.metadata == %{}
    end

    test "news_item_ids defaults to empty list" do
      assert %ChatMessage{}.news_item_ids == []
    end
  end
end
