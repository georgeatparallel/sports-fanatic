defmodule SportsFanatic.Repo.Migrations.CreateXApiCalls do
  use Ecto.Migration

  def change do
    create table(:x_api_calls, prefix: "system", primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :endpoint, :string, size: 100, null: false
      add :method, :string, size: 10, null: false
      add :http_status, :integer
      add :tweet_id, :string, size: 50
      add :had_url, :boolean, default: false
      # mills = 1/1000 of a dollar. 15 mills text, 200 mills URL-bearing
      add :cost_mills, :integer, default: 0
      # "system" | "joshua:{ts}" | "watcher" — free text, max 100 chars
      add :actor, :string, size: 100, null: false
      add :error_message, :text
      add :duration_ms, :integer

      add :inserted_at, :utc_datetime, null: false, default: fragment("NOW()")
    end

    create index(:x_api_calls, [:inserted_at], prefix: "system")
    create index(:x_api_calls, [:tweet_id], prefix: "system")
    create index(:x_api_calls, [:had_url, :inserted_at], prefix: "system")
  end
end
