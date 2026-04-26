defmodule Mix.Tasks.Db.Backup do
  use Mix.Task

  @shortdoc "Create a database backup"
  @moduledoc """
  Creates a PostgreSQL backup using pg_dump in custom format.

  ## Usage

      mix db.backup [--no-s3] [--schemas LIST]

  See `scripts/db_backup.sh --help` for full options.
  """

  @impl Mix.Task
  def run(args) do
    script = Path.join([File.cwd!(), "scripts", "db_backup.sh"])

    unless File.exists?(script) do
      Mix.raise("Backup script not found at #{script}")
    end

    {_, exit_code} =
      System.cmd("bash", [script | args],
        into: IO.stream(:stdio, :line),
        stderr_to_stdout: true
      )

    if exit_code not in [0, 3] do
      Mix.raise("Backup failed with exit code #{exit_code}")
    end

    if exit_code == 3 do
      Mix.shell().info("Warning: Backup saved locally but S3 upload failed")
    end
  end
end
