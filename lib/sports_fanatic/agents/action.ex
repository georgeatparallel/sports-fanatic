defmodule SportsFanatic.Agents.Action do
  @moduledoc """
  Behaviour for agent actions. Provides a Jido-compatible action interface
  that works with the project's Elixir 1.15 runtime.

  Each action module implements `run/2` which receives params and context,
  and returns `{:ok, result}` or `{:error, reason}`.
  """

  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback run(params :: map(), context :: map()) :: {:ok, map()} | {:error, term()}

  defmacro __using__(opts) do
    name = Keyword.fetch!(opts, :name)
    description = Keyword.fetch!(opts, :description)

    quote do
      @behaviour SportsFanatic.Agents.Action

      @impl true
      def name, do: unquote(name)

      @impl true
      def description, do: unquote(description)
    end
  end
end
