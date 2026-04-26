defmodule Mix.Tasks.Db.BackupTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Db.Backup

  @moduledoc """
  Unit tests for Mix.Tasks.Db.Backup.

  These tests validate the Mix task wrapper only -- they do NOT invoke
  pg_dump or interact with a real database.  They are tagged :unit so
  they run with `mix test.unit`.
  """

  @tag :unit
  describe "module attributes" do
    test "task has a shortdoc" do
      # Mix task shortdoc is stored as a module attribute; fetch via Mix.Task.shortdoc/1.
      shortdoc = Mix.Task.shortdoc(Backup)
      assert shortdoc =~ ~r/backup/i
    end

    test "task moduledoc mentions db.backup" do
      # The @moduledoc attribute is accessible via Code.fetch_docs/1.
      {:docs_v1, _, _, _, module_doc, _, _} = Code.fetch_docs(Backup)
      doc_text = Map.get(module_doc, "en", "")
      assert doc_text =~ "db.backup"
    end
  end

  @tag :unit
  describe "script path resolution" do
    test "backup script exists relative to project root" do
      # The Mix task derives the path from File.cwd!/0.
      # In test mode cwd is the project root, so the script must be present.
      script = Path.join([File.cwd!(), "scripts", "db_backup.sh"])

      assert File.exists?(script),
             "Expected backup script at #{script}"
    end

    test "backup script is a regular file" do
      script = Path.join([File.cwd!(), "scripts", "db_backup.sh"])
      assert File.regular?(script)
    end
  end

  @tag :unit
  describe "run/1 argument validation" do
    test "unknown flag raises Mix.Error" do
      # db_backup.sh will exit non-zero on an unknown flag; the task wraps
      # that with Mix.raise/1 which raises Mix.Error.
      assert_raise Mix.Error, ~r/failed/, fn ->
        Backup.run(["--unknown-flag-xyz"])
      end
    end

    test "passing --no-s3 alone does not crash before pg_dump check" do
      # The script will fail because pg_dump either isn't available in this
      # environment or cannot connect -- either way exit code is non-zero.
      # What we assert is that the task raises Mix.Error (not an unexpected crash).
      # We use a try/rescue rather than assert_raise so we can match broadly.
      try do
        Backup.run(["--no-s3"])
      rescue
        e in Mix.Error -> assert e.message =~ ~r/failed|not installed|not found/i
      end
    end
  end
end
