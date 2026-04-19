defmodule SportsFanatic.Repo do
  use Ecto.Repo,
    otp_app: :sports_fanatic,
    adapter: Ecto.Adapters.Postgres
end
