defmodule SportsFanatic.X.TokenVault do
  @moduledoc """
  In-house AES-256-GCM wrapper for the X OAuth tokens. Avoids adding the
  cloak/cloak_ecto deps (which would bring their own GenServer choreography
  and key-rotation migrations) for a single column pair on a single row.

  ## Key sourcing

  Reads the 32-byte key from the `X_TOKEN_ENCRYPTION_KEY` env var (Base64
  encoded; raw decoded length must be 32 bytes). When the env var is
  missing or malformed, `encrypt/1` and `decrypt/2` return `{:error,
  :missing_key}` instead of raising — this keeps boot-time failures from
  crashing the supervisor when the X agent is disabled.

  ## Associated data binding

  All ciphertexts are AAD-bound to the constant `@aad` below. Mismatched
  AAD (e.g. ciphertext from a different table) fails decryption.
  """

  require Logger

  @aad "sports_fanatic.x_credentials.v1"
  @iv_length 12
  @tag_length 16

  @doc """
  Encrypts a plaintext string. Returns `{:ok, %{ciphertext, iv}}` where both
  values are raw binaries. The IV is generated fresh per-call via
  `:crypto.strong_rand_bytes/1` and must be stored alongside the ciphertext.
  """
  @spec encrypt(String.t()) ::
          {:ok, %{ciphertext: binary(), iv: binary()}}
          | {:error, :missing_key | :invalid_key | term()}
  def encrypt(plaintext) when is_binary(plaintext) do
    with {:ok, key} <- fetch_key() do
      iv = :crypto.strong_rand_bytes(@iv_length)

      {ciphertext, tag} =
        :crypto.crypto_one_time_aead(
          :aes_256_gcm,
          key,
          iv,
          plaintext,
          @aad,
          @tag_length,
          true
        )

      {:ok, %{ciphertext: ciphertext <> tag, iv: iv}}
    end
  rescue
    e ->
      Logger.error("X.TokenVault encrypt failed: #{inspect(e)}")
      {:error, :encrypt_failed}
  end

  @doc """
  Decrypts a ciphertext produced by `encrypt/1`. Returns `{:ok, plaintext}`
  on success or `{:error, reason}` on tampering, mismatched AAD, or bad
  key.
  """
  @spec decrypt(binary(), binary()) ::
          {:ok, String.t()} | {:error, :missing_key | :invalid_key | :decrypt_failed}
  def decrypt(ciphertext_with_tag, iv)
      when is_binary(ciphertext_with_tag) and is_binary(iv) do
    with {:ok, key} <- fetch_key(),
         {:ok, ciphertext, tag} <- split_ciphertext(ciphertext_with_tag) do
      case :crypto.crypto_one_time_aead(
             :aes_256_gcm,
             key,
             iv,
             ciphertext,
             @aad,
             tag,
             false
           ) do
        :error ->
          {:error, :decrypt_failed}

        plaintext when is_binary(plaintext) ->
          {:ok, plaintext}
      end
    end
  rescue
    e ->
      Logger.error("X.TokenVault decrypt failed: #{inspect(e)}")
      {:error, :decrypt_failed}
  end

  # ── private ─────────────────────────────────────────────────

  defp fetch_key do
    case Application.get_env(:sports_fanatic, :x_agent)[:token_encryption_key] do
      nil ->
        {:error, :missing_key}

      "" ->
        {:error, :missing_key}

      raw when is_binary(raw) ->
        case Base.decode64(raw) do
          {:ok, decoded} when byte_size(decoded) == 32 -> {:ok, decoded}
          {:ok, _} -> {:error, :invalid_key}
          :error -> {:error, :invalid_key}
        end

      _ ->
        {:error, :invalid_key}
    end
  end

  # TODO(VAULT-001): the `> @tag_length` guard rejects ciphertexts that wrap an
  # empty plaintext (AES-256-GCM of "" produces exactly 16 bytes — tag only).
  # Production OAuth tokens are never empty so this is a deferred edge case;
  # see docs/KNOWN_ISSUES.md (X agent / Deferred).
  defp split_ciphertext(bin) when byte_size(bin) > @tag_length do
    body_size = byte_size(bin) - @tag_length
    <<body::binary-size(body_size), tag::binary-size(@tag_length)>> = bin
    {:ok, body, tag}
  end

  defp split_ciphertext(_), do: {:error, :decrypt_failed}
end
