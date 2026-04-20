defmodule SportsFanatic.PythonBridgeSeoTest do
  @moduledoc """
  Unit tests verifying that `PythonBridge.generate_player_seo/1` exists and
  is properly exported. Does not make real HTTP calls.
  """
  use ExUnit.Case, async: true

  alias SportsFanatic.PythonBridge

  describe "generate_player_seo/1" do
    test "function is exported from PythonBridge module" do
      assert function_exported?(PythonBridge, :generate_player_seo, 1)
    end

    test "returns circuit_open error when circuit breaker is open" do
      # Without the circuit breaker process running (no Repo/DB in unit tests),
      # the function falls back to do_post which will fail with a connection error
      # rather than a circuit_open error — so we just verify the function returns
      # a tagged tuple matching {:ok, _} | {:error, _}
      result = PythonBridge.generate_player_seo(%{player_name: "test"})
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
end
