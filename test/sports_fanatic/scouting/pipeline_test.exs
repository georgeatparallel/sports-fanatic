defmodule SportsFanatic.Scouting.PipelineTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias SportsFanatic.Scouting.Pipeline

  # Ensure module is loaded for function_exported? checks
  setup_all do
    Code.ensure_loaded!(Pipeline)
    :ok
  end

  describe "Pipeline module" do
    test "exports start_pipeline/1" do
      assert function_exported?(Pipeline, :start_pipeline, 1)
    end

    test "exports start_pipeline/0 (default config)" do
      assert function_exported?(Pipeline, :start_pipeline, 0)
    end

    test "exports cancel_pipeline/0" do
      assert function_exported?(Pipeline, :cancel_pipeline, 0)
    end

    test "exports get_status/0" do
      assert function_exported?(Pipeline, :get_status, 0)
    end

    test "exports subscribe/0" do
      assert function_exported?(Pipeline, :subscribe, 0)
    end

    test "exports start_link/1" do
      assert function_exported?(Pipeline, :start_link, 1)
    end
  end

  describe "Pipeline moduledoc" do
    test "documents today's lineup focus" do
      {:docs_v1, _, _, _, %{"en" => moduledoc}, _, _} = Code.fetch_docs(Pipeline)
      assert moduledoc =~ "today's scheduled lineups"
      refute moduledoc =~ "all active MLB players"
    end
  end
end
