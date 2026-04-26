defmodule Mix.Tasks.Db.RestoreTest do
  use ExUnit.Case, async: true

  @moduledoc """
  Unit tests for Mix.Tasks.Db.Restore.

  These tests validate the Mix task wrapper only — they do NOT invoke
  pg_restore or interact with a real database.  They are tagged :unit so
  they run with `mix test.unit`.
  """

  @tag :unit
  describe "module attributes" do
    test "task has a shortdoc" do
      shortdoc = Mix.Task.shortdoc(Mix.Tasks.Db.Restore)
      assert shortdoc =~ ~r/restore/i
    end

    test "task moduledoc mentions db.restore" do
      {:docs_v1, _, _, _, module_doc, _, _} = Code.fetch_docs(Mix.Tasks.Db.Restore)
      doc_text = Map.get(module_doc, "en", "")
      assert doc_text =~ "db.restore"
    end
  end

  @tag :unit
  describe "script path resolution" do
    test "restore script exists relative to project root" do
      script = Path.join([File.cwd!(), "scripts", "db_restore.sh"])

      assert File.exists?(script),
             "Expected restore script at #{script}"
    end

    test "restore script is a regular file" do
      script = Path.join([File.cwd!(), "scripts", "db_restore.sh"])
      assert File.regular?(script)
    end
  end

  @tag :unit
  describe "run/1 with empty argument list" do
    test "raises Mix.Error with usage message" do
      assert_raise Mix.Error, ~r/Usage.*db\.restore/i, fn ->
        Mix.Tasks.Db.Restore.run([])
      end
    end

    test "error message includes dump_file_or_s3_key placeholder" do
      assert_raise Mix.Error, ~r/dump_file_or_s3_key/, fn ->
        Mix.Tasks.Db.Restore.run([])
      end
    end
  end

  @tag :unit
  describe "run/1 with non-existent dump file" do
    test "raises Mix.Error when file does not exist" do
      # The shell script exits 1 for a missing file; the task wraps that.
      assert_raise Mix.Error, ~r/failed/, fn ->
        Mix.Tasks.Db.Restore.run(["/tmp/does_not_exist_sf_mix_test_abc123.dump", "--force"])
      end
    end
  end

  @tag :unit
  describe "run/1 with invalid dump file (bad PGDMP header)" do
    setup do
      path =
        Path.join(
          System.tmp_dir!(),
          "sf_mix_restore_test_invalid_#{System.unique_integer()}.dump"
        )

      File.write!(path, "THIS IS NOT A VALID PG DUMP\n")
      on_exit(fn -> File.rm(path) end)
      {:ok, path: path}
    end

    test "raises Mix.Error for invalid dump content", %{path: path} do
      assert_raise Mix.Error, ~r/failed/, fn ->
        Mix.Tasks.Db.Restore.run([path, "--force"])
      end
    end
  end

  @tag :unit
  describe "run/1 with empty dump file" do
    setup do
      path =
        Path.join(System.tmp_dir!(), "sf_mix_restore_test_empty_#{System.unique_integer()}.dump")

      File.write!(path, "")
      on_exit(fn -> File.rm(path) end)
      {:ok, path: path}
    end

    test "raises Mix.Error for empty dump file", %{path: path} do
      assert_raise Mix.Error, ~r/failed/, fn ->
        Mix.Tasks.Db.Restore.run([path, "--force"])
      end
    end
  end

  @tag :unit
  describe "run/1 argument validation via shell script" do
    test "unknown flag raises Mix.Error" do
      # Provide a dummy source so arg parsing reaches the unknown-flag check.
      assert_raise Mix.Error, ~r/failed/, fn ->
        Mix.Tasks.Db.Restore.run(["/tmp/dummy.dump", "--unknown-flag-xyz"])
      end
    end

    test "--jobs with non-integer value raises Mix.Error" do
      assert_raise Mix.Error, ~r/failed/, fn ->
        Mix.Tasks.Db.Restore.run(["/tmp/dummy.dump", "--jobs", "notanumber"])
      end
    end
  end
end
