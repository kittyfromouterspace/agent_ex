defmodule Agentic.Strategy.DefaultTest do
  use ExUnit.Case, async: true

  alias Agentic.Strategy.Default

  describe "callbacks" do
    test "id/0 returns :default" do
      assert Default.id() == :default
    end

    test "display_name/0" do
      assert Default.display_name() == "Default"
    end

    test "description/0" do
      assert is_binary(Default.description())
    end

    test "init/1 returns ok with nil state" do
      assert {:ok, nil} = Default.init([])
    end

    test "prepare_run/2 returns opts unchanged" do
      opts = [prompt: "test", workspace: "/tmp"]
      assert {:ok, ^opts, nil} = Default.prepare_run(opts, nil)
    end

    test "handle_result/3 with ok returns done" do
      result = %{text: "hello", cost: 0.01, tokens: 10, steps: 1}
      assert {:done, ^result, nil} = Default.handle_result({:ok, result}, [], nil)
    end

    test "handle_result/3 with error returns error" do
      assert {:error, :timeout} = Default.handle_result({:error, :timeout}, [], nil)
    end
  end
end
