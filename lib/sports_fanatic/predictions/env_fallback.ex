defmodule SportsFanatic.Predictions.EnvFallback do
  @moduledoc """
  Pure helper for resolving environment variable fallbacks in the predictions
  pipeline configuration. Extracted so it can be unit-tested without booting
  the application.

  ## OPENMETEO_API_KEY fallback

  Reads `OPENMETEO_API_KEY` first. If unset and `OPENMATEO_API_KEY` is set,
  uses the legacy spelling and emits a single `Logger.warning`. When both are
  unset, returns `nil` (free-tier mode).

  This logic is called from `config/runtime.exs`; having it in a named function
  lets tests verify the branching without instrumenting the config boot.
  """

  require Logger

  @doc """
  Resolves the Open-Meteo API key from environment variables.

  Returns `{key, warned?}` where:
  - `key` is the resolved API key string or `nil`
  - `warned?` is `true` if a deprecation warning was emitted
  """
  @spec resolve_open_meteo_api_key() :: {String.t() | nil, boolean()}
  def resolve_open_meteo_api_key do
    resolve_open_meteo_api_key(&System.get_env/1)
  end

  @doc """
  Testable variant that accepts a custom env-reader function.

  The reader receives a variable name string and returns the value or `nil`.
  This allows tests to control the environment without setting process env vars.
  """
  @spec resolve_open_meteo_api_key((String.t() -> String.t() | nil)) ::
          {String.t() | nil, boolean()}
  def resolve_open_meteo_api_key(env_reader) when is_function(env_reader, 1) do
    case env_reader.("OPENMETEO_API_KEY") do
      nil ->
        case env_reader.("OPENMATEO_API_KEY") do
          nil ->
            {nil, false}

          legacy ->
            Logger.warning(
              "OPENMATEO_API_KEY is set (deprecated spelling). " <>
                "Rename to OPENMETEO_API_KEY."
            )

            {legacy, true}
        end

      key ->
        {key, false}
    end
  end
end
