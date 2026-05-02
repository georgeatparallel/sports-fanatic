defmodule SportsFanatic.StorageTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.Storage

  # ---------------------------------------------------------------------------
  # news_article_key/2 — pure function, no S3 required
  # ---------------------------------------------------------------------------

  describe "news_article_key/2" do
    test "generates correct path for a mid-year date" do
      date = ~D[2026-05-15]
      key = Storage.news_article_key(date, "fn-12345")
      assert key == "news/raw/2026/05/15/fn-12345.json"
    end

    test "zero-pads single-digit month" do
      date = ~D[2026-01-20]
      key = Storage.news_article_key(date, "fn-abc")
      assert key == "news/raw/2026/01/20/fn-abc.json"
    end

    test "zero-pads single-digit day" do
      date = ~D[2026-07-04]
      key = Storage.news_article_key(date, "fn-abc")
      assert key == "news/raw/2026/07/04/fn-abc.json"
    end

    test "zero-pads both month and day when both are single digits" do
      date = ~D[2026-03-09]
      key = Storage.news_article_key(date, "fn-xyz")
      assert key == "news/raw/2026/03/09/fn-xyz.json"
    end

    test "does not zero-pad two-digit month or day" do
      date = ~D[2026-11-25]
      key = Storage.news_article_key(date, "fn-999")
      assert key == "news/raw/2026/11/25/fn-999.json"
    end

    test "sanitizes external_id to remove unsafe characters" do
      date = ~D[2026-05-01]
      # Dots, slashes, and path traversal sequences are stripped
      key = Storage.news_article_key(date, "some-complex_id.with-dots")
      assert key == "news/raw/2026/05/01/some-complex_idwith-dots.json"
    end

    test "strips path traversal sequences from external_id" do
      date = ~D[2026-05-01]
      key = Storage.news_article_key(date, "../../etc/passwd")
      assert key == "news/raw/2026/05/01/etcpasswd.json"
    end

    test "strips slashes from external_id" do
      date = ~D[2026-05-01]
      key = Storage.news_article_key(date, "fn/12345")
      assert key == "news/raw/2026/05/01/fn12345.json"
    end

    test "preserves alphanumeric, hyphens, and underscores in external_id" do
      date = ~D[2026-05-01]
      key = Storage.news_article_key(date, "fn-12345_abc")
      assert key == "news/raw/2026/05/01/fn-12345_abc.json"
    end

    test "always ends with .json extension" do
      date = ~D[2026-05-01]
      key = Storage.news_article_key(date, "fn-42")
      assert String.ends_with?(key, ".json")
    end

    test "always starts with news/raw/ prefix" do
      date = ~D[2026-05-01]
      key = Storage.news_article_key(date, "fn-42")
      assert String.starts_with?(key, "news/raw/")
    end

    test "path segments follow YYYY/MM/DD format" do
      date = ~D[2026-12-31]
      key = Storage.news_article_key(date, "fn-last")
      assert key == "news/raw/2026/12/31/fn-last.json"
    end
  end

  # ---------------------------------------------------------------------------
  # sanitize_key/1 — prevents path traversal in S3 keys
  # ---------------------------------------------------------------------------

  describe "sanitize_key/1" do
    test "passes through safe alphanumeric strings" do
      assert Storage.sanitize_key("fn-12345") == "fn-12345"
    end

    test "preserves underscores" do
      assert Storage.sanitize_key("fn_12345") == "fn_12345"
    end

    test "strips dots" do
      assert Storage.sanitize_key("file.json") == "filejson"
    end

    test "strips slashes" do
      assert Storage.sanitize_key("a/b/c") == "abc"
    end

    test "strips path traversal sequences" do
      assert Storage.sanitize_key("../../../etc/passwd") == "etcpasswd"
    end

    test "strips spaces and special characters" do
      assert Storage.sanitize_key("hello world!@#$%") == "helloworld"
    end

    test "handles integer input by converting to string" do
      assert Storage.sanitize_key(12345) == "12345"
    end

    test "handles empty string" do
      assert Storage.sanitize_key("") == ""
    end
  end

  # ---------------------------------------------------------------------------
  # put_news_article/2 — unit-testable behavior when S3 is disabled
  # ---------------------------------------------------------------------------

  describe "put_news_article/2 when S3 is disabled" do
    setup do
      original = Application.get_env(:sports_fanatic, :news_s3_enabled, false)
      Application.put_env(:sports_fanatic, :news_s3_enabled, false)
      on_exit(fn -> Application.put_env(:sports_fanatic, :news_s3_enabled, original) end)
      :ok
    end

    test "returns {:ok, nil} without making any S3 call" do
      result = Storage.put_news_article("fn-12345", %{headline: "Test Article"})
      assert result == {:ok, nil}
    end

    test "accepts any map payload and still returns {:ok, nil}" do
      payload = %{
        "id" => "fn-99",
        "headline" => "Big Trade",
        "nested" => %{"key" => "value"}
      }

      assert {:ok, nil} = Storage.put_news_article("fn-99", payload)
    end
  end
end
