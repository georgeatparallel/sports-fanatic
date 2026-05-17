defmodule SportsFanatic.X.SpendLedger do
  @moduledoc """
  Inserts one row per X API write call into `system.x_api_calls` and exposes
  today's spend total + cap arithmetic.

  Costs are tracked in **mills** (1/1000 of a dollar):

    * 15 mills per pure-text write (X v2 free-tier "no link" tweets)
    * 200 mills per URL-bearing write (X "link tax")

  Daily cap defaults to 5000 mills ($5) and is configurable via
  `:sports_fanatic, :x_agent, :daily_cap_mills` (set in `runtime.exs` from
  the `X_DAILY_CAP_MILLS` env var). When today's spend reaches the cap,
  `budget_remaining?/0` returns `false` and `SportsFanatic.X.post_tweet/2`
  refuses to call X.
  """

  import Ecto.Query
  alias SportsFanatic.Repo
  alias SportsFanatic.X.ApiCall

  @default_cap_mills 5000

  @doc """
  Inserts a single audit row. Always returns the inserted struct or raises
  via `Ecto.InvalidChangesetError` if the changeset is invalid — this is
  intentional: a missing audit row indicates a programmer error and we
  should crash the calling worker (Oban will retry).
  """
  @spec record!(keyword()) :: ApiCall.t()
  def record!(opts) do
    attrs = Enum.into(opts, %{})
    %ApiCall{} |> ApiCall.changeset(attrs) |> Repo.insert!()
  end

  @doc """
  Sums `cost_mills` for today's UTC-day x_api_calls rows.
  """
  @spec today_mills() :: integer()
  def today_mills do
    today = Date.utc_today()
    {:ok, day_start, _} = DateTime.from_iso8601("#{Date.to_iso8601(today)}T00:00:00Z")

    Repo.one(
      from c in ApiCall,
        where: c.inserted_at >= ^day_start,
        select: coalesce(sum(c.cost_mills), 0)
    )
    |> ensure_int()
  end

  @doc "Configured daily cap in mills."
  @spec daily_cap_mills() :: integer()
  def daily_cap_mills do
    cfg = Application.get_env(:sports_fanatic, :x_agent, [])
    cfg[:daily_cap_mills] || @default_cap_mills
  end

  @doc "Returns mills remaining until the daily cap, never below 0."
  @spec budget_remaining_mills() :: integer()
  def budget_remaining_mills do
    max(daily_cap_mills() - today_mills(), 0)
  end

  @doc "Returns true while today's spend is strictly below the daily cap."
  @spec budget_remaining?() :: boolean()
  def budget_remaining? do
    today_mills() < daily_cap_mills()
  end

  # Repo.one can return %Decimal{} for sum() on integer; normalize.
  defp ensure_int(nil), do: 0
  defp ensure_int(n) when is_integer(n), do: n

  defp ensure_int(%Decimal{} = d) do
    d |> Decimal.to_integer()
  end

  defp ensure_int(other), do: trunc(other)
end
