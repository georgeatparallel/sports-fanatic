defmodule SportsFanatic.X.SanitizerTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.X

  # X.sanitize_and_validate/1 signature:
  # sanitize_and_validate(body, opts \\ []) :: {:ok, sanitized, had_url?} | {:error, atom}

  # ---------------------------------------------------------------------------
  # Control character stripping
  # ---------------------------------------------------------------------------

  describe "control character stripping" do
    test "strips ASCII control chars 0x00–0x09" do
      input = "\x00Hello\x01 World\x09"
      # \x09 is TAB — also stripped per the module's regex [\x00-\x09]
      {:ok, out, _} = X.sanitize_and_validate(input)
      refute String.contains?(out, "\x00")
      refute String.contains?(out, "\x01")
    end

    test "preserves newlines (\\n = 0x0A)" do
      input = "Line one\nLine two"
      {:ok, out, _} = X.sanitize_and_validate(input)
      assert String.contains?(out, "\n")
    end

    test "strips vertical tab (0x0B)" do
      input = "Hello\x0BWorld"
      {:ok, out, _} = X.sanitize_and_validate(input)
      refute String.contains?(out, "\x0B")
    end

    test "strips carriage return (0x0D)" do
      input = "Hello\rWorld"
      {:ok, out, _} = X.sanitize_and_validate(input)
      refute String.contains?(out, "\r")
    end

    test "strips 0x1F (unit separator)" do
      input = "Good\x1Fdata"
      {:ok, out, _} = X.sanitize_and_validate(input)
      refute String.contains?(out, "\x1F")
    end

    test "strips DEL (0x7F)" do
      input = "Hello\x7FWorld"
      {:ok, out, _} = X.sanitize_and_validate(input)
      refute String.contains?(out, "\x7F")
    end

    test "preserves printable ASCII" do
      input = "Judge hits 60th HR! No. 60 in 2026."
      {:ok, out, _} = X.sanitize_and_validate(input)
      assert String.contains?(out, "60th HR")
    end
  end

  # ---------------------------------------------------------------------------
  # NFC normalization
  # ---------------------------------------------------------------------------

  describe "NFC normalization" do
    test "decomposed accented char is NFC-normalized" do
      # 'é' can be represented as U+0065 U+0301 (decomposed) or U+00E9 (NFC)
      # e + combining acute accent (UTF-8 for NFD é)
      decomposed = <<101, 204, 129>>
      # NFC form
      composed = "é"

      {:ok, out, _} = X.sanitize_and_validate("Player #{decomposed} stats")
      {:ok, nfc_out, _} = X.sanitize_and_validate("Player #{composed} stats")

      # Both should produce the same NFC output
      assert out == nfc_out
    end

    test "plain ASCII is unaffected by NFC normalization" do
      input = "Aaron Judge is 1 for 3"
      {:ok, out, _} = X.sanitize_and_validate(input)
      assert out == input
    end
  end

  # ---------------------------------------------------------------------------
  # 280-character length enforcement
  # ---------------------------------------------------------------------------

  describe "length enforcement" do
    test "accepts exactly 280 grapheme characters" do
      # 280 ASCII chars
      body = String.duplicate("a", 280)
      assert {:ok, _, _} = X.sanitize_and_validate(body)
    end

    test "rejects 281+ grapheme characters" do
      body = String.duplicate("a", 281)
      assert {:error, :too_long} = X.sanitize_and_validate(body)
    end

    test "returns {:error, :empty} for empty string (after trim)" do
      assert {:error, :empty} = X.sanitize_and_validate("")
    end

    test "returns {:error, :empty} for whitespace-only string" do
      assert {:error, :empty} = X.sanitize_and_validate("   ")
    end
  end

  # ---------------------------------------------------------------------------
  # URL detection and rejection
  # ---------------------------------------------------------------------------

  describe "URL detection / rejection in main body" do
    test "rejects https:// URL in body when allow_url is false (default)" do
      body = "Check out our injury report at https://sportsfanatic.com/mlb/injury-report"
      assert {:error, :url_in_body} = X.sanitize_and_validate(body)
    end

    test "rejects http:// URL in body when allow_url is false" do
      body = "Stats at http://example.com/mlb/stats"
      assert {:error, :url_in_body} = X.sanitize_and_validate(body)
    end

    test "allows https:// URL when :allow_url is true (reply path)" do
      body = "https://sportsfanatic.com/mlb/injury-report"
      assert {:ok, _, true} = X.sanitize_and_validate(body, allow_url: true)
    end

    test "had_url? is false when no URL in body" do
      body = "Judge goes deep for HR #60"
      assert {:ok, _, false} = X.sanitize_and_validate(body)
    end

    test "had_url? is true when URL present and allow_url is true" do
      body = "See the full breakdown: https://sportsfanatic.com"
      assert {:ok, _, true} = X.sanitize_and_validate(body, allow_url: true)
    end

    test "body without URL and allow_url: true still returns had_url: false" do
      body = "Judge hits his 60th home run of the season"
      assert {:ok, _, false} = X.sanitize_and_validate(body, allow_url: true)
    end
  end

  # ---------------------------------------------------------------------------
  # HTML tag stripping (HtmlSanitizeEx.strip_tags/1 in pipeline)
  # ---------------------------------------------------------------------------

  describe "HTML tag stripping" do
    test "strips <script> tags and their surrounding angle brackets" do
      input = "Hello <script>alert(1)</script> World"
      {:ok, out, _} = X.sanitize_and_validate(input)

      refute String.contains?(out, "<script>"),
             "Expected <script> tag to be stripped, got: #{out}"

      refute String.contains?(out, "</script>"),
             "Expected </script> tag to be stripped, got: #{out}"

      # Note: HtmlSanitizeEx.strip_tags/1 removes HTML tags but preserves
      # the inner text content ("alert(1)"). This is the library's documented
      # behaviour. The defense-in-depth against JS injection is the refusal to
      # call raw/1 in templates (acceptance criterion #9).
      # The script tag itself (the dangerous part) is stripped.
      assert String.contains?(out, "Hello") and String.contains?(out, "World")
    end

    test "strips <b> tags but preserves text content" do
      input = "Judge hits <b>huge</b> HR"
      {:ok, out, _} = X.sanitize_and_validate(input)
      refute String.contains?(out, "<b>")
      assert String.contains?(out, "huge")
    end
  end

  # ---------------------------------------------------------------------------
  # sanitize_and_validate/1 return shape
  # ---------------------------------------------------------------------------

  describe "return value shape" do
    test "success returns 3-tuple {:ok, string, boolean}" do
      result = X.sanitize_and_validate("Valid tweet body here")
      assert {:ok, body, had_url} = result
      assert is_binary(body)
      assert is_boolean(had_url)
    end
  end
end
