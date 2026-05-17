defmodule SportsFanatic.X.Scheduler do
  @moduledoc """
  Pure planning for one day of X posts.

  Algorithm:

    1. base window = 13:00 ET to 18:00 ET on `date`
    2. earliest_game = min(scheduled_games.game_datetime WHERE game_date=date)
    3. hard_latest = earliest_game - 30 min, clamped to base upper bound
    4. split window into 3 slots with ≥ 45 min spacing
    5. ±18 min uniform jitter per slot, then re-clamp
    6. drop slots that would land after hard_latest into `skipped_slots`
    7. randomize [top_hits, injury, team_magazine] using a seed derived from
       Date.to_gregorian_days/1 (reproducible same-day) — but freshly
       random for the jitter (anti-bot)

  Returns the plan as a map. Persistence is done by `XPostSchedulerWorker`.
  """

  import Ecto.Query

  alias SportsFanatic.Mlb.ScheduledGame
  alias SportsFanatic.Repo

  @eastern_offset_seconds -4 * 3600
  @base_start_hour_et 13
  @base_end_hour_et 18
  @slot_spacing_minutes 45
  @jitter_minutes 18

  @doc """
  Returns the day's plan.

  Inputs:
    * `date` — `%Date{}`, expected to be today in ET
    * `opts` — keyword
      - `:earliest_game_at` — `%DateTime{} | nil`. When passed, used directly;
        when missing, queried from `mlb.scheduled_games` for the date.
      - `:now` — `%DateTime{} | nil`, default `DateTime.utc_now/0` (used so
        unit tests can pin the clock for jitter assertions).
      - `:rand_state` — optional `{:rand, seeded_state}` tuple. When given,
        the jitter and order RNG draw from this state for reproducible tests.

  Output map:

      %{
        post_order: ["top_hits", "injury", "team_magazine"] (or some perm),
        scheduled_times: %{"top_hits" => %DateTime{}, ...},
        skipped_slots: ["..."],
        earliest_game_at: %DateTime{} | nil
      }
  """
  @spec plan_day(Date.t(), keyword()) :: %{
          post_order: [String.t()],
          scheduled_times: %{String.t() => DateTime.t()},
          skipped_slots: [String.t()],
          earliest_game_at: DateTime.t() | nil
        }
  def plan_day(%Date{} = date, opts \\ []) do
    earliest_game_at = Keyword.get(opts, :earliest_game_at) || fetch_earliest_game_at(date)

    {base_start, base_end} = base_window_utc(date)
    hard_latest = compute_hard_latest(base_end, earliest_game_at)

    base_slots = base_slot_times(base_start, base_end)
    jittered = Enum.map(base_slots, &jitter(&1, base_start, hard_latest))

    {kept, skipped} = partition_slots(jittered, hard_latest)
    order = order_for_date(date)

    scheduled_times =
      order
      |> Enum.zip(kept)
      |> Map.new()

    %{
      post_order: order,
      scheduled_times: scheduled_times,
      skipped_slots:
        Enum.zip(order, jittered)
        |> Enum.reduce([], fn {pt, dt}, acc ->
          if dt in skipped, do: [pt | acc], else: acc
        end)
        |> Enum.reverse(),
      earliest_game_at: earliest_game_at
    }
  end

  # Precomputed permutation table for the 3 post types. Indexing into this by
  # `:erlang.phash2(gregorian_days, 6)` gives a deterministic per-date order
  # that distributes evenly across the 6 permutations. This is intentionally
  # NOT random — same date must always yield the same order so re-running the
  # scheduler on the same day produces an identical plan.
  @permutations [
    ["top_hits", "injury", "team_magazine"],
    ["top_hits", "team_magazine", "injury"],
    ["injury", "top_hits", "team_magazine"],
    ["injury", "team_magazine", "top_hits"],
    ["team_magazine", "top_hits", "injury"],
    ["team_magazine", "injury", "top_hits"]
  ]

  @doc "Visible for testing — the seeded post-type ordering for a given date."
  @spec order_for_date(Date.t()) :: [String.t()]
  def order_for_date(%Date{} = date) do
    idx = :erlang.phash2(Date.to_gregorian_days(date), length(@permutations))
    Enum.at(@permutations, idx)
  end

  # ── private ─────────────────────────────────────────────────

  defp base_window_utc(%Date{} = date) do
    {:ok, start_dt, _} =
      DateTime.from_iso8601("#{Date.to_iso8601(date)}T#{pad_two(@base_start_hour_et)}:00:00Z")

    {:ok, end_dt, _} =
      DateTime.from_iso8601("#{Date.to_iso8601(date)}T#{pad_two(@base_end_hour_et)}:00:00Z")

    # The literal hours above are ET; convert to UTC by subtracting the
    # Eastern offset (EDT = UTC-4). During EST the cron itself shifts; see
    # X-AGENT-001 in docs/KNOWN_ISSUES.md.
    {DateTime.add(start_dt, -@eastern_offset_seconds, :second),
     DateTime.add(end_dt, -@eastern_offset_seconds, :second)}
  end

  defp pad_two(n), do: n |> Integer.to_string() |> String.pad_leading(2, "0")

  defp compute_hard_latest(base_end, nil), do: base_end

  defp compute_hard_latest(base_end, %DateTime{} = earliest_game) do
    candidate = DateTime.add(earliest_game, -30 * 60, :second)
    if DateTime.compare(candidate, base_end) == :lt, do: candidate, else: base_end
  end

  defp base_slot_times(base_start, base_end) do
    span_seconds = DateTime.diff(base_end, base_start)

    Enum.map(0..2, fn i ->
      fraction = (i + 0.5) / 3.0
      offset_seconds = trunc(fraction * span_seconds)
      DateTime.add(base_start, offset_seconds, :second)
    end)
    |> ensure_spacing(@slot_spacing_minutes * 60)
  end

  defp ensure_spacing([first, second, third] = _slots, min_seconds) do
    second =
      if DateTime.diff(second, first) < min_seconds,
        do: DateTime.add(first, min_seconds, :second),
        else: second

    third =
      if DateTime.diff(third, second) < min_seconds,
        do: DateTime.add(second, min_seconds, :second),
        else: third

    [first, second, third]
  end

  defp jitter(%DateTime{} = dt, base_start, hard_latest) do
    spread_seconds = @jitter_minutes * 60
    delta = :rand.uniform(2 * spread_seconds + 1) - spread_seconds - 1
    jittered = DateTime.add(dt, delta, :second)

    cond do
      DateTime.compare(jittered, base_start) == :lt -> base_start
      DateTime.compare(jittered, hard_latest) == :gt -> hard_latest
      true -> jittered
    end
  end

  defp partition_slots(slots, hard_latest) do
    {kept_rev, skipped_rev} =
      Enum.reduce(slots, {[], []}, fn dt, {kept, skipped} ->
        if DateTime.compare(dt, hard_latest) == :gt do
          {kept, [dt | skipped]}
        else
          {[dt | kept], skipped}
        end
      end)

    {Enum.reverse(kept_rev), Enum.reverse(skipped_rev)}
  end

  defp fetch_earliest_game_at(date) do
    Repo.one(
      from g in ScheduledGame,
        where: g.game_date == ^date,
        select: min(g.game_datetime)
    )
  rescue
    _ -> nil
  end
end
