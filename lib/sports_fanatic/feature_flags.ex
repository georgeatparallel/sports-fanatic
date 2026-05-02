defmodule SportsFanatic.FeatureFlags do
  @moduledoc """
  Feature flags context with ETS-backed caching.

  Provides a general-purpose feature flag system backed by PostgreSQL
  with ETS caching for fast lookups. Cache entries have a 30-second TTL.

  ## Usage

      SportsFanatic.FeatureFlags.enabled?("subscriptions_enabled")

  """

  use GenServer
  import Ecto.Query
  alias SportsFanatic.FeatureFlags.FeatureFlag
  alias SportsFanatic.Repo
  require Logger

  @table :feature_flags_cache
  @cache_ttl_ms 30_000

  # ── Client API ──────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Check if a feature flag is enabled. Returns `false` if the flag
  does not exist or if the database is unreachable.

  Uses ETS caching with a 30-second TTL for performance.
  """
  @spec enabled?(String.t()) :: boolean()
  def enabled?(key) when is_binary(key) do
    case get_cached(key) do
      {:ok, value} ->
        value

      :miss ->
        value = fetch_from_db(key)
        put_cached(key, value)
        value
    end
  end

  @doc "Enable a feature flag by key."
  @spec enable(String.t()) :: {:ok, FeatureFlag.t()} | {:error, :not_found}
  def enable(key) do
    set_enabled(key, true)
  end

  @doc "Disable a feature flag by key."
  @spec disable(String.t()) :: {:ok, FeatureFlag.t()} | {:error, :not_found}
  def disable(key) do
    set_enabled(key, false)
  end

  @doc "List all feature flags ordered by key."
  @spec list_all() :: [FeatureFlag.t()]
  def list_all do
    FeatureFlag
    |> order_by(:key)
    |> Repo.all()
  end

  @doc "Get a single feature flag by key."
  @spec get(String.t()) :: FeatureFlag.t() | nil
  def get(key) do
    Repo.get_by(FeatureFlag, key: key)
  end

  @doc "Create a new feature flag."
  @spec create(map()) :: {:ok, FeatureFlag.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    %FeatureFlag{}
    |> FeatureFlag.create_changeset(attrs)
    |> Repo.insert()
    |> tap_invalidate_cache()
  end

  @doc "Update a feature flag by key."
  @spec update(String.t(), map()) ::
          {:ok, FeatureFlag.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def update(key, attrs) do
    case get(key) do
      nil ->
        {:error, :not_found}

      flag ->
        flag
        |> FeatureFlag.update_changeset(attrs)
        |> Repo.update()
        |> tap_invalidate_cache()
    end
  end

  @doc "Delete a feature flag by key."
  @spec delete(String.t()) :: {:ok, FeatureFlag.t()} | {:error, :not_found}
  def delete(key) do
    case get(key) do
      nil ->
        {:error, :not_found}

      flag ->
        case Repo.delete(flag) do
          {:ok, deleted} ->
            invalidate_cache(key)
            {:ok, deleted}

          error ->
            error
        end
    end
  end

  @doc "Invalidate the cached value for a key."
  def invalidate_cache(key) do
    if :ets.whereis(@table) != :undefined do
      :ets.delete(@table, key)
    end

    :ok
  end

  @doc "Invalidate all cached feature flag values."
  def invalidate_all_cache do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end

    :ok
  end

  # ── GenServer Callbacks ─────────────────────────────────────

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    {:ok, %{table: table}}
  end

  # ── Private ─────────────────────────────────────────────────

  defp get_cached(key) do
    if :ets.whereis(@table) == :undefined do
      :miss
    else
      lookup_ets(key)
    end
  end

  defp lookup_ets(key) do
    case :ets.lookup(@table, key) do
      [{^key, value, inserted_at}] ->
        age = System.monotonic_time(:millisecond) - inserted_at
        if age <= @cache_ttl_ms, do: {:ok, value}, else: :miss

      [] ->
        :miss
    end
  end

  defp put_cached(key, value) do
    if :ets.whereis(@table) != :undefined do
      :ets.insert(@table, {key, value, System.monotonic_time(:millisecond)})
    end

    :ok
  end

  defp fetch_from_db(key) do
    case Repo.one(from f in FeatureFlag, where: f.key == ^key, select: f.enabled) do
      nil -> false
      enabled -> enabled
    end
  rescue
    _error ->
      Logger.warning(
        "FeatureFlags: failed to fetch flag #{key} from database, defaulting to false"
      )

      false
  end

  defp set_enabled(key, enabled) do
    case get(key) do
      nil ->
        {:error, :not_found}

      flag ->
        result =
          flag
          |> FeatureFlag.update_changeset(%{enabled: enabled})
          |> Repo.update()

        case result do
          {:ok, updated} ->
            invalidate_cache(key)
            {:ok, updated}

          error ->
            error
        end
    end
  end

  defp tap_invalidate_cache({:ok, %FeatureFlag{key: key}} = result) do
    invalidate_cache(key)
    result
  end

  defp tap_invalidate_cache(result), do: result
end
