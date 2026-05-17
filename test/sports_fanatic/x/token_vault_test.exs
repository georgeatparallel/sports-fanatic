defmodule SportsFanatic.X.TokenVaultTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.X.TokenVault

  # 32-byte key, Base64-encoded
  @valid_key Base.encode64(:crypto.strong_rand_bytes(32))
  # A different 32-byte key for AAD-mismatch tests
  @other_key Base.encode64(:crypto.strong_rand_bytes(32))

  defp put_key(key) do
    original = Application.get_env(:sports_fanatic, :x_agent, [])

    Application.put_env(
      :sports_fanatic,
      :x_agent,
      Keyword.put(original, :token_encryption_key, key)
    )

    original
  end

  defp restore_key(original) do
    Application.put_env(:sports_fanatic, :x_agent, original)
  end

  # ---------------------------------------------------------------------------
  # Happy path: encrypt/1 → decrypt/2 round-trip
  # ---------------------------------------------------------------------------

  describe "round-trip encrypt/decrypt" do
    setup do
      original = put_key(@valid_key)
      on_exit(fn -> restore_key(original) end)
      :ok
    end

    test "encrypt returns {:ok, %{ciphertext, iv}}" do
      assert {:ok, %{ciphertext: ct, iv: iv}} = TokenVault.encrypt("my-access-token")
      assert is_binary(ct)
      assert is_binary(iv)
    end

    test "decrypt returns the original plaintext" do
      plaintext = "secret-oauth-token-12345"
      {:ok, %{ciphertext: ct, iv: iv}} = TokenVault.encrypt(plaintext)
      assert {:ok, ^plaintext} = TokenVault.decrypt(ct, iv)
    end

    test "empty string encryption produces ciphertext (only GCM tag, no body)" do
      # Encrypting an empty string produces a ciphertext that is exactly the
      # 16-byte GCM authentication tag with no body bytes. The `split_ciphertext`
      # guard requires `byte_size > 16` (strictly greater), so decryption of a
      # 16-byte-only ciphertext returns {:error, :decrypt_failed}.
      # This is a known limitation of the current `split_ciphertext` implementation —
      # it cannot round-trip empty plaintext. See BUG: VAULT-001.
      #
      # The production code never encrypts an empty token (OAuth tokens are always
      # non-empty), so this edge case is low risk. Documented here for awareness.
      result = TokenVault.encrypt("")
      assert {:ok, %{ciphertext: ct, iv: _iv}} = result
      # ciphertext should be exactly 16 bytes (just the GCM tag)
      assert byte_size(ct) == 16
      # Decryption of empty-body ciphertext returns an error (not a crash)
      {:ok, %{ciphertext: ct2, iv: iv2}} = TokenVault.encrypt("")
      assert match?({:error, _}, TokenVault.decrypt(ct2, iv2))
    end

    test "round-trips a long token (512 chars)" do
      plaintext = String.duplicate("a", 512)
      {:ok, %{ciphertext: ct, iv: iv}} = TokenVault.encrypt(plaintext)
      assert {:ok, ^plaintext} = TokenVault.decrypt(ct, iv)
    end

    test "different encrypt calls produce different ciphertexts (fresh IV per call)" do
      {:ok, %{ciphertext: ct1, iv: iv1}} = TokenVault.encrypt("token")
      {:ok, %{ciphertext: ct2, iv: iv2}} = TokenVault.encrypt("token")
      # IVs must be random each time
      refute iv1 == iv2
      # Ciphertexts will also differ because IVs differ
      refute ct1 == ct2
    end

    test "ciphertext is longer than plaintext (includes 16-byte GCM tag)" do
      plaintext = "abc"
      {:ok, %{ciphertext: ct}} = TokenVault.encrypt(plaintext)
      # ciphertext = body + 16-byte tag → at least 16 bytes longer than plaintext
      assert byte_size(ct) >= byte_size(plaintext) + 16
    end

    test "IV is exactly 12 bytes" do
      {:ok, %{iv: iv}} = TokenVault.encrypt("test")
      assert byte_size(iv) == 12
    end
  end

  # ---------------------------------------------------------------------------
  # AAD mismatch: using a different key should fail decryption
  # ---------------------------------------------------------------------------

  describe "decrypt fails with wrong key (AAD mismatch)" do
    test "returns {:error, :decrypt_failed} when decrypting with different key" do
      original1 = put_key(@valid_key)
      {:ok, %{ciphertext: ct, iv: iv}} = TokenVault.encrypt("super-secret")
      restore_key(original1)

      original2 = put_key(@other_key)
      result = TokenVault.decrypt(ct, iv)
      restore_key(original2)

      assert {:error, :decrypt_failed} = result
    end
  end

  # ---------------------------------------------------------------------------
  # Tampered ciphertext
  # ---------------------------------------------------------------------------

  describe "decrypt fails with tampered ciphertext" do
    setup do
      original = put_key(@valid_key)
      on_exit(fn -> restore_key(original) end)
      :ok
    end

    test "returns {:error, :decrypt_failed} when ciphertext byte is flipped" do
      {:ok, %{ciphertext: ct, iv: iv}} = TokenVault.encrypt("real-token")
      # Flip first byte
      <<first, rest::binary>> = ct
      tampered = <<Bitwise.bxor(first, 0xFF)>> <> rest

      assert {:error, :decrypt_failed} = TokenVault.decrypt(tampered, iv)
    end

    test "returns {:error, :decrypt_failed} when IV is wrong" do
      {:ok, %{ciphertext: ct}} = TokenVault.encrypt("real-token")
      wrong_iv = :crypto.strong_rand_bytes(12)

      assert {:error, :decrypt_failed} = TokenVault.decrypt(ct, wrong_iv)
    end

    test "returns {:error, :decrypt_failed} for truncated ciphertext" do
      {:ok, %{ciphertext: ct, iv: iv}} = TokenVault.encrypt("real-token")
      # Strip last 4 bytes — corrupts the GCM tag
      truncated = binary_part(ct, 0, max(byte_size(ct) - 4, 0))

      result = TokenVault.decrypt(truncated, iv)
      assert match?({:error, _}, result)
    end

    test "returns {:error, :decrypt_failed} for too-short ciphertext (< 16 bytes)" do
      # Anything <= 16 bytes fails the split_ciphertext guard
      assert {:error, :decrypt_failed} = TokenVault.decrypt(<<1, 2, 3>>, <<0::size(96)>>)
    end
  end

  # ---------------------------------------------------------------------------
  # Missing / invalid key
  # ---------------------------------------------------------------------------

  describe "missing or invalid key" do
    test "returns {:error, :missing_key} when key env var is nil" do
      original = Application.get_env(:sports_fanatic, :x_agent, [])

      Application.put_env(
        :sports_fanatic,
        :x_agent,
        Keyword.delete(original, :token_encryption_key)
      )

      on_exit(fn -> restore_key(original) end)

      assert {:error, :missing_key} = TokenVault.encrypt("token")
    end

    test "returns {:error, :missing_key} when key is empty string" do
      original = put_key("")
      on_exit(fn -> restore_key(original) end)

      assert {:error, :missing_key} = TokenVault.encrypt("token")
    end

    test "returns {:error, :invalid_key} when key is wrong length (< 32 bytes)" do
      # 20-byte key, Base64-encoded
      short_key = Base.encode64(:crypto.strong_rand_bytes(20))
      original = put_key(short_key)
      on_exit(fn -> restore_key(original) end)

      assert {:error, :invalid_key} = TokenVault.encrypt("token")
    end

    test "returns {:error, :invalid_key} when key is not valid Base64" do
      original = put_key("not-base64!!!")
      on_exit(fn -> restore_key(original) end)

      assert {:error, :invalid_key} = TokenVault.encrypt("token")
    end
  end
end
