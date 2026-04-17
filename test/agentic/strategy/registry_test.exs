defmodule Agentic.Strategy.RegistryTest do
  use ExUnit.Case, async: false

  alias Agentic.Strategy.Registry, as: StrategyRegistry

  setup do
    Elixir.Registry.start_link(keys: :unique, name: Agentic.Memory.ContextKeeperRegistry)
    Elixir.Registry.start_link(keys: :unique, name: Agentic.Subagent.Registry)
    StrategyRegistry.start_link([])
    :ok
  end

  describe "fetch/1" do
    test "returns Default for :default" do
      assert StrategyRegistry.fetch(:default) == Agentic.Strategy.Default
    end

    test "returns nil for unregistered strategy" do
      assert StrategyRegistry.fetch(:nonexistent) == nil
    end
  end

  describe "fetch!/1" do
    test "returns module for registered strategy" do
      assert StrategyRegistry.fetch!(:default) == Agentic.Strategy.Default
    end

    test "raises for unregistered strategy" do
      assert_raise RuntimeError, ~r/Strategy not registered/, fn ->
        StrategyRegistry.fetch!(:nonexistent)
      end
    end
  end

  describe "register/1" do
    test "registers a new strategy" do
      defmodule TestStrategy do
        @behaviour Agentic.Strategy
        def id, do: :test_strategy
        def display_name, do: "Test"
        def description, do: "Test strategy"
        def init(_), do: {:ok, nil}
        def prepare_run(opts, state), do: {:ok, opts, state}

        def handle_result(result, _, state),
          do: {:ok, state} |> then(fn {:ok, s} -> {:done, elem(result, 1), s} end)
      end

      StrategyRegistry.register(TestStrategy)
      assert StrategyRegistry.fetch(:test_strategy) == TestStrategy
    end
  end

  describe "all/0" do
    test "returns map with at least :default" do
      all = StrategyRegistry.all()
      assert Map.has_key?(all, :default)
      assert all[:default] == Agentic.Strategy.Default
    end
  end
end
