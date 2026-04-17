defmodule Agentic.Strategy.IntegrationTest do
  use ExUnit.Case, async: false

  import Agentic.TestHelpers

  describe "run/1 with strategy: :default" do
    test "produces same result as run without strategy" do
      workspace = create_test_workspace()

      callbacks = mock_callbacks()

      base_opts = [
        prompt: "Say hello",
        workspace: workspace,
        callbacks: callbacks,
        cost_limit: 0.10
      ]

      assert {:ok, %{text: _, cost: _, tokens: _, steps: _}} = Agentic.run(base_opts)
    end

    test "strategy: :default produces identical behavior" do
      workspace = create_test_workspace()

      callbacks = mock_callbacks()

      opts = [
        prompt: "Say hello",
        workspace: workspace,
        callbacks: callbacks,
        strategy: :default,
        cost_limit: 0.10
      ]

      assert {:ok, %{text: _, cost: _, tokens: _, steps: _}} = Agentic.run(opts)
    end

    test "strategy_opts are passed to init" do
      workspace = create_test_workspace()

      callbacks = mock_callbacks()

      opts = [
        prompt: "Say hello",
        workspace: workspace,
        callbacks: callbacks,
        strategy: :default,
        strategy_opts: [custom: true],
        cost_limit: 0.10
      ]

      assert {:ok, _} = Agentic.run(opts)
    end
  end

  describe "strategy resolution through run/1" do
    test "nil strategy uses Default (no strategy key)" do
      workspace = create_test_workspace()
      callbacks = mock_callbacks()

      opts = [
        prompt: "Say hello",
        workspace: workspace,
        callbacks: callbacks,
        cost_limit: 0.10
      ]

      assert {:ok, %{text: _, cost: _, tokens: _, steps: _}} = Agentic.run(opts)
    end

    test "registered atom id resolves from registry" do
      workspace = create_test_workspace()
      callbacks = mock_callbacks()

      opts = [
        prompt: "Say hello",
        workspace: workspace,
        callbacks: callbacks,
        strategy: :default,
        cost_limit: 0.10
      ]

      assert {:ok, %{text: _, cost: _, tokens: _, steps: _}} = Agentic.run(opts)
    end

    test "unregistered atom is used as module directly" do
      defmodule InlineStrategy do
        @behaviour Agentic.Strategy
        def id, do: :inline
        def display_name, do: "Inline"
        def description, do: "Test inline strategy"
        def init(_), do: {:ok, nil}
        def prepare_run(opts, state), do: {:ok, opts, state}
        def handle_result({:ok, result}, _opts, state), do: {:done, result, state}
        def handle_result({:error, reason}, _opts, _state), do: {:error, reason}
      end

      workspace = create_test_workspace()
      callbacks = mock_callbacks()

      opts = [
        prompt: "Say hello",
        workspace: workspace,
        callbacks: callbacks,
        strategy: InlineStrategy,
        cost_limit: 0.10
      ]

      assert {:ok, %{text: _, cost: _, tokens: _, steps: _}} = Agentic.run(opts)
    end
  end
end
