defmodule AgentEx.Protocol.ACP.DiscoveryTest do
  use ExUnit.Case, async: true

  alias AgentEx.Protocol.ACP.Discovery

  setup do
    Discovery.init()
    Discovery.clear_cache()
    :ok
  end

  describe "known_agents/0" do
    test "returns the built-in agent database" do
      agents = Discovery.known_agents()

      assert length(agents) >= 15

      names = Enum.map(agents, & &1.name)
      assert :kimi in names
      assert :claude in names
      assert :codex in names
      assert :cursor in names
      assert :gemini in names
      assert :copilot in names
      assert :opencode in names
      assert :droid in names
    end

    test "each agent has required fields" do
      for agent <- Discovery.known_agents() do
        assert is_atom(agent.name)
        assert is_binary(agent.command) and agent.command != ""
        assert is_list(agent.args) and length(agent.args) > 0
        assert is_binary(agent.display) and agent.display != ""
      end
    end
  end

  describe "lookup/1" do
    test "returns nil for unknown agent" do
      assert Discovery.lookup(:nonexistent) == nil
    end

    test "returns nil before any discovery" do
      assert Discovery.lookup(:kimi) == nil
    end

    test "returns entry after caching" do
      entry = %{
        name: :test_agent,
        command: "test-cmd",
        args: ["--acp"],
        display: "Test Agent",
        aliases: []
      }

      :ets.insert(Discovery.table_name(), {{:agent, :test_agent}, entry})

      result = Discovery.lookup(:test_agent)
      assert result.name == :test_agent
      assert result.command == "test-cmd"
    after
      :ets.delete(Discovery.table_name(), {:agent, :test_agent})
    end
  end

  describe "launch_command/1" do
    test "returns nil for unknown agent" do
      assert Discovery.launch_command(:nonexistent) == nil
    end
  end

  describe "backend_config/2" do
    test "returns empty map for unknown agent" do
      config = Discovery.backend_config(:nonexistent)
      assert config == %{}
    end

    test "returns empty map for nil agent" do
      config = Discovery.backend_config(nil)
      assert config == %{}
    end
  end

  describe "available?/1" do
    test "returns false for unknown agent" do
      refute Discovery.available?(:nonexistent)
    end
  end

  describe "configured_agents" do
    test "parses ACP_AGENTS env var" do
      System.put_env("ACP_AGENTS", "myagent --custom-arg, another arg1 arg2")

      agents = Discovery.configured_agents()

      names = Enum.map(agents, & &1.name)
      assert :myagent in names
      assert :another in names

      myagent = Enum.find(agents, &(&1.name == :myagent))
      assert myagent.args == ["--custom-arg"]

      another = Enum.find(agents, &(&1.name == :another))
      assert another.args == ["arg1", "arg2"]
    end

    test "handles empty ACP_AGENTS" do
      System.put_env("ACP_AGENTS", "")

      assert Discovery.configured_agents() == []
    after
      System.delete_env("ACP_AGENTS")
    end
  end
end
