defmodule AgentEx.Strategy.IntegrationTest do
  use ExUnit.Case, async: false

  import AgentEx.TestHelpers

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

      assert {:ok, %{text: _, cost: _, tokens: _, steps: _}} = AgentEx.run(base_opts)
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

      assert {:ok, %{text: _, cost: _, tokens: _, steps: _}} = AgentEx.run(opts)
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

      assert {:ok, _} = AgentEx.run(opts)
    end
  end

  describe "resolve_strategy" do
    test "nil strategy resolves to Default" do
      assert AgentEx.resolve_strategy_for_test([]) == AgentEx.Strategy.Default
    end

    test "atom id resolves from registry" do
      assert AgentEx.resolve_strategy_for_test(strategy: :default) == AgentEx.Strategy.Default
    end
  end
end
