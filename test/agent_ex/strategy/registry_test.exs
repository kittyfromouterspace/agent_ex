defmodule AgentEx.Strategy.RegistryTest do
  use ExUnit.Case, async: false

  alias AgentEx.Strategy.Registry

  setup do
    Registry.start_link(keys: :unique, name: AgentEx.Memory.ContextKeeperRegistry)
    Registry.start_link(keys: :unique, name: AgentEx.Subagent.Registry)
    AgentEx.Strategy.Registry.start_link([])
    :ok
  end

  describe "fetch/1" do
    test "returns Default for :default" do
      assert Registry.fetch(:default) == AgentEx.Strategy.Default
    end

    test "returns nil for unregistered strategy" do
      assert Registry.fetch(:nonexistent) == nil
    end
  end

  describe "fetch!/1" do
    test "returns module for registered strategy" do
      assert Registry.fetch!(:default) == AgentEx.Strategy.Default
    end

    test "raises for unregistered strategy" do
      assert_raise RuntimeError, ~r/Strategy not registered/, fn ->
        Registry.fetch!(:nonexistent)
      end
    end
  end

  describe "register/1" do
    test "registers a new strategy" do
      defmodule TestStrategy do
        @behaviour AgentEx.Strategy
        def id, do: :test_strategy
        def display_name, do: "Test"
        def description, do: "Test strategy"
        def init(_), do: {:ok, nil}
        def prepare_run(opts, state), do: {:ok, opts, state}
        def handle_result(result, _, state), do: {:ok, state} |> then(fn {:ok, s} -> {:done, elem(result, 1), s} end)
      end

      Registry.register(TestStrategy)
      assert Registry.fetch(:test_strategy) == TestStrategy
    end
  end

  describe "all/0" do
    test "returns map with at least :default" do
      all = Registry.all()
      assert Map.has_key?(all, :default)
      assert all[:default] == AgentEx.Strategy.Default
    end
  end
end
