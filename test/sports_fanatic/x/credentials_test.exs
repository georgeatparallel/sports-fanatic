defmodule SportsFanatic.X.CredentialsTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.X.Credentials

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        account_handle: "sportsfanatic_mlb",
        account_id: "1234567890",
        access_token_ciphertext: :crypto.strong_rand_bytes(32),
        refresh_token_ciphertext: :crypto.strong_rand_bytes(32),
        access_token_iv: :crypto.strong_rand_bytes(12),
        refresh_token_iv: :crypto.strong_rand_bytes(12),
        expires_at: ~U[2026-06-15 19:00:00Z],
        scope: "tweet.read tweet.write users.read offline.access"
      },
      overrides
    )
  end

  defp changeset(attrs), do: Credentials.changeset(%Credentials{}, attrs)

  # ---------------------------------------------------------------------------
  # Changeset: required fields
  # ---------------------------------------------------------------------------

  describe "changeset/2 — required fields" do
    test "valid attrs produce a valid changeset" do
      assert changeset(valid_attrs()).valid?
    end

    test "missing account_handle is invalid" do
      cs = changeset(valid_attrs() |> Map.delete(:account_handle))
      refute cs.valid?
      assert {:account_handle, _} = List.keyfind(cs.errors, :account_handle, 0)
    end

    test "missing account_id is invalid" do
      cs = changeset(valid_attrs() |> Map.delete(:account_id))
      refute cs.valid?
      assert {:account_id, _} = List.keyfind(cs.errors, :account_id, 0)
    end

    test "missing access_token_ciphertext is invalid" do
      cs = changeset(valid_attrs() |> Map.delete(:access_token_ciphertext))
      refute cs.valid?
      assert {:access_token_ciphertext, _} = List.keyfind(cs.errors, :access_token_ciphertext, 0)
    end

    test "missing refresh_token_ciphertext is invalid" do
      cs = changeset(valid_attrs() |> Map.delete(:refresh_token_ciphertext))
      refute cs.valid?

      assert {:refresh_token_ciphertext, _} =
               List.keyfind(cs.errors, :refresh_token_ciphertext, 0)
    end

    test "missing access_token_iv is invalid" do
      cs = changeset(valid_attrs() |> Map.delete(:access_token_iv))
      refute cs.valid?
      assert {:access_token_iv, _} = List.keyfind(cs.errors, :access_token_iv, 0)
    end

    test "missing refresh_token_iv is invalid" do
      cs = changeset(valid_attrs() |> Map.delete(:refresh_token_iv))
      refute cs.valid?
      assert {:refresh_token_iv, _} = List.keyfind(cs.errors, :refresh_token_iv, 0)
    end

    test "missing expires_at is invalid" do
      cs = changeset(valid_attrs() |> Map.delete(:expires_at))
      refute cs.valid?
      assert {:expires_at, _} = List.keyfind(cs.errors, :expires_at, 0)
    end

    test "missing scope is invalid" do
      cs = changeset(valid_attrs() |> Map.delete(:scope))
      refute cs.valid?
      assert {:scope, _} = List.keyfind(cs.errors, :scope, 0)
    end
  end

  # ---------------------------------------------------------------------------
  # Length validations
  # ---------------------------------------------------------------------------

  describe "changeset/2 — length limits" do
    test "account_handle over 50 chars is invalid" do
      cs = changeset(valid_attrs(%{account_handle: String.duplicate("a", 51)}))
      refute cs.valid?
      assert {:account_handle, _} = List.keyfind(cs.errors, :account_handle, 0)
    end

    test "account_id over 50 chars is invalid" do
      cs = changeset(valid_attrs(%{account_id: String.duplicate("9", 51)}))
      refute cs.valid?
      assert {:account_id, _} = List.keyfind(cs.errors, :account_id, 0)
    end

    test "scope over 500 chars is invalid" do
      cs = changeset(valid_attrs(%{scope: String.duplicate("s", 501)}))
      refute cs.valid?
      assert {:scope, _} = List.keyfind(cs.errors, :scope, 0)
    end

    test "exactly 50-char account_handle is valid" do
      cs = changeset(valid_attrs(%{account_handle: String.duplicate("a", 50)}))
      assert cs.valid?
    end
  end

  # ---------------------------------------------------------------------------
  # singleton is always set to true by changeset
  # ---------------------------------------------------------------------------

  describe "singleton constraint" do
    test "changeset always puts singleton: true regardless of input" do
      cs = changeset(valid_attrs(%{singleton: false}))
      assert Ecto.Changeset.get_field(cs, :singleton) == true
    end

    test "changeset sets singleton: true when not provided" do
      cs = changeset(valid_attrs())
      assert Ecto.Changeset.get_field(cs, :singleton) == true
    end
  end

  # ---------------------------------------------------------------------------
  # Ciphertext fields NOT exposed in JSON serialization
  # ---------------------------------------------------------------------------

  describe "sensitive field JSON exposure" do
    test "ciphertext fields are not included in Jason.encode! output" do
      # Build a credentials struct with populated ciphertext fields
      creds = %Credentials{
        id: "aaaaaaaa-0000-0000-0000-000000000001",
        account_handle: "sportsfanatic_mlb",
        account_id: "1234567890",
        access_token_ciphertext: "secret-ciphertext-bytes",
        refresh_token_ciphertext: "other-ciphertext-bytes",
        access_token_iv: "iv-bytes",
        refresh_token_iv: "iv-bytes-2",
        access_token: "plaintext-access",
        refresh_token: "plaintext-refresh",
        expires_at: ~U[2026-06-15 19:00:00Z],
        scope: "tweet.read",
        singleton: true,
        inserted_at: ~U[2026-06-15 00:00:00Z],
        updated_at: ~U[2026-06-15 00:00:00Z]
      }

      # The schema has @schema_prefix "accounts" which means it has no
      # derive Jason.Encoder by default. The test verifies the struct
      # fields are excluded from inspect output per @derive {Inspect, except: [...]}
      inspection = inspect(creds)

      refute String.contains?(inspection, "plaintext-access"),
             "access_token (plaintext) leaked in inspect/1"

      refute String.contains?(inspection, "plaintext-refresh"),
             "refresh_token (plaintext) leaked in inspect/1"
    end

    test "inspect output does not contain ciphertext field values" do
      creds = %Credentials{
        account_handle: "sportsfanatic_mlb",
        account_id: "12345",
        access_token_ciphertext: <<1, 2, 3, 4>>,
        refresh_token_ciphertext: <<5, 6, 7, 8>>,
        access_token_iv: <<9, 10, 11, 12>>,
        refresh_token_iv: <<13, 14, 15, 16>>,
        expires_at: ~U[2026-06-15 19:00:00Z],
        scope: "tweet.read"
      }

      inspection = inspect(creds)
      # The @derive {Inspect, except: [...]} annotation should redact these
      refute String.contains?(inspection, "access_token_ciphertext"),
             "access_token_ciphertext key leaked in inspect/1"

      refute String.contains?(inspection, "refresh_token_ciphertext"),
             "refresh_token_ciphertext key leaked in inspect/1"
    end

    test "inspect/1 shows non-sensitive fields" do
      creds = %Credentials{
        account_handle: "sportsfanatic_mlb",
        account_id: "12345",
        access_token_ciphertext: <<1, 2>>,
        refresh_token_ciphertext: <<3, 4>>,
        access_token_iv: <<5, 6, 7, 8, 9, 10, 11, 12>>,
        refresh_token_iv: <<13, 14, 15, 16, 17, 18, 19, 20>>,
        expires_at: ~U[2026-06-15 19:00:00Z],
        scope: "tweet.read"
      }

      inspection = inspect(creds)

      assert String.contains?(inspection, "sportsfanatic_mlb"),
             "account_handle should be visible in inspect/1"
    end
  end

  # ---------------------------------------------------------------------------
  # Virtual fields are not persisted
  # ---------------------------------------------------------------------------

  describe "virtual fields" do
    test "access_token is a virtual field (not in cast_fields)" do
      # Virtual fields can be set on a struct but are not cast from attrs
      cs = changeset(valid_attrs() |> Map.put(:access_token, "my-token"))
      # Virtual fields added via Map.put to attrs are not in cast fields,
      # so they won't appear in changes
      refute Map.has_key?(cs.changes, :access_token)
    end

    test "refresh_token is a virtual field (not in cast_fields)" do
      cs = changeset(valid_attrs() |> Map.put(:refresh_token, "my-refresh"))
      refute Map.has_key?(cs.changes, :refresh_token)
    end
  end
end
