defmodule AgentEx.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: AgentEx.Memory.ContextKeeperRegistry},
      {Registry, keys: :unique, name: AgentEx.Subagent.Registry},
      AgentEx.Subagent.CoordinatorSupervisor,
      AgentEx.LLM.ProviderRegistry,
      AgentEx.LLM.Catalog,
      AgentEx.LLM.UsageManager,
      AgentEx.ModelRouter,
      AgentEx.Protocol.Registry,
      AgentEx.Strategy.Registry,
      AgentEx.Telemetry.Aggregator
    ]

    opts = [strategy: :one_for_one, name: AgentEx.Supervisor]

    # Initialize ETS tables
    AgentEx.CircuitBreaker.init()

    # Register built-in protocols
    register_protocols()

    Supervisor.start_link(children, opts)
  end

  defp register_protocols do
    AgentEx.Protocol.Registry.register(:llm, AgentEx.Protocol.LLM)

    if AgentEx.Protocol.ClaudeCode.available?() do
      AgentEx.Protocol.Registry.register(:claude_code, AgentEx.Protocol.ClaudeCode)
    end

    if AgentEx.Protocol.OpenCode.available?() do
      AgentEx.Protocol.Registry.register(:opencode, AgentEx.Protocol.OpenCode)
    end

    if AgentEx.Protocol.Codex.available?() do
      AgentEx.Protocol.Registry.register(:codex, AgentEx.Protocol.Codex)
    end

    AgentEx.Protocol.Registry.register({:acp, :generic}, AgentEx.Protocol.ACP)

    register_acp_agents()
  end

  defp register_acp_agents do
    agents = Application.get_env(:agent_ex, :acp_agents, [])

    Enum.each(agents, fn agent ->
      command = agent[:command] || agent["command"]
      name = agent[:name] || agent["name"]

      if command && name do
        if System.find_executable(command) do
          AgentEx.Protocol.Registry.register({:acp, name}, AgentEx.Protocol.ACP)
        end
      end
    end)
  end
end
