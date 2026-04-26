defmodule Mix.Tasks.Db.Restore do
  use Mix.Task

  @shortdoc "Restore a database from backup"
  @moduledoc """
  Restores a PostgreSQL database from a pg_dump custom format file.

  ## Usage

      mix db.restore <dump_file_or_s3_key> [--force] [--drop] [--jobs N]

  See `scripts/db_restore.sh --help` for full options.
  """

  @impl Mix.Task
  def run([]) do
    Mix.raise("Usage: mix db.restore <dump_file_or_s3_key> [--force] [--drop] [--jobs N]")
  end

  def run(args) do
    script = Path.join([File.cwd!(), "scripts", "db_restore.sh"])

    unless File.exists?(script) do
      Mix.raise("Restore script not found at #{script}")
    end

    {_, exit_code} =
      System.cmd("bash", [script | args],
        into: IO.stream(:stdio, :line),
        stderr_to_stdout: true
      )

    case exit_code do
      0 -> :ok
      4 -> Mix.shell().info("Restore cancelled by user")
      _ -> Mix.raise("Restore failed with exit code #{exit_code}")
    end
  end
end
