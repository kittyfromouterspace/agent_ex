defmodule AgentEx.Protocol.ACP.Discovery do
  @moduledoc """
  Auto-discovery of ACP-compatible agents on the system.

  Probes the filesystem for known ACP-capable CLIs and registers
  discovered agents in the protocol registry.

  The known agents database is derived from the acpx project
  (https://github.com/openclaw/acpx) and covers 15+ agents.

  ## Discovery Sources

  1. Built-in known agents database (this module)
  2. `config :agent_ex, :acp_agents` (user overrides)
  3. `ACP_AGENTS` environment variable (comma-separated)
  4. `:discover_callback` in acp config (programmatic)
  """

  require Logger

  @table :agent_ex_acp_discovery

  @doc "Returns the ETS table name (for testing)."
  def table_name, do: @table

  @type agent_entry :: %{
          name: atom(),
          command: String.t(),
          args: [String.t()],
          display: String.t(),
          aliases: [atom()],
          cache_dirs: [String.t()],
          notes: String.t() | nil
        }

  # --- Known Agents Database ---
  # Derived from https://github.com/openclaw/acpx/blob/main/src/agent-registry.ts
  # Each entry maps a normalized name to the shell command used to launch it in ACP mode.

  @known_agents [
    %{
      name: :kimi,
      command: "kimi",
      args: ["acp"],
      display: "Kimi Code",
      aliases: [],
      cache_dirs: []
    },
    %{
      name: :claude,
      command: "claude",
      args: ["acp"],
      display: "Claude Code",
      aliases: [:claude_code],
      cache_dirs: ["~/.claude/projects"],
      notes: "Requires @agentclientprotocol/claude-agent-acp package or claude binary"
    },
    %{
      name: :codex,
      command: "codex",
      args: ["acp"],
      display: "Codex CLI",
      aliases: [],
      cache_dirs: ["~/.codex"],
      notes: "Or via npx @zed-industries/codex-acp"
    },
    %{
      name: :cursor,
      command: "cursor-agent",
      args: ["acp"],
      display: "Cursor",
      aliases: [],
      cache_dirs: []
    },
    %{
      name: :gemini,
      command: "gemini",
      args: ["--acp"],
      display: "Gemini CLI",
      aliases: [],
      cache_dirs: ["~/.gemini"],
      notes: "Gemini < 0.33.0 needs --experimental-acp"
    },
    %{
      name: :copilot,
      command: "copilot",
      args: ["--acp", "--stdio"],
      display: "GitHub Copilot",
      aliases: [],
      cache_dirs: [],
      notes: "Pre-flight --help check for ACP support"
    },
    %{
      name: :opencode,
      command: "opencode",
      args: ["acp"],
      display: "OpenCode",
      aliases: [],
      cache_dirs: ["~/.local/share/opencode"],
      notes: "Or via npx -y opencode-ai acp"
    },
    %{
      name: :goose,
      command: "goose",
      args: ["acp"],
      display: "Goose",
      aliases: [],
      cache_dirs: ["~/.config/goose"]
    },
    %{
      name: :kiro,
      command: "kiro-cli-chat",
      args: ["acp"],
      display: "Kiro CLI",
      aliases: [],
      cache_dirs: []
    },
    %{
      name: :qwen,
      command: "qwen",
      args: ["--acp"],
      display: "Qwen Code",
      aliases: [],
      cache_dirs: []
    },
    %{
      name: :qoder,
      command: "qodercli",
      args: ["--acp"],
      display: "Qoder CLI",
      aliases: [],
      cache_dirs: [],
      notes: "Supports --max-turns and --allowed-tools args"
    },
    %{
      name: :droid,
      command: "droid",
      args: ["exec", "--output-format", "acp"],
      display: "Factory Droid",
      aliases: [:factory_droid, :factorydroid],
      cache_dirs: []
    },
    %{
      name: :openclaw,
      command: "openclaw",
      args: ["acp"],
      display: "OpenClaw",
      aliases: [],
      cache_dirs: []
    },
    %{
      name: :pi,
      command: "pi",
      args: ["acp"],
      display: "Pi",
      aliases: [],
      cache_dirs: [],
      notes: "Or via npx pi-acp"
    },
    %{
      name: :trae,
      command: "traecli",
      args: ["acp", "serve"],
      display: "Trae",
      aliases: [],
      cache_dirs: []
    },
    %{
      name: :iflow,
      command: "iflow",
      args: ["--experimental-acp"],
      display: "iFlow",
      aliases: [],
      cache_dirs: [],
      notes: "Experimental ACP support"
    }
  ]

  # --- Public API ---

  @doc "Initialize the ETS table for discovery cache."
  @spec init() :: :ok
  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    end

    :ok
  end

  @doc "Return all known agent entries (before probing)."
  @spec known_agents() :: [agent_entry()]
  def known_agents, do: @known_agents

  @doc "Look up an agent in the built-in database by name or alias (no ETS required)."
  @spec lookup_known(atom()) :: agent_entry() | nil
  def lookup_known(name) do
    Enum.find(@known_agents, fn entry ->
      entry.name == name or name in Map.get(entry, :aliases, [])
    end)
  end

  @doc """
  Discover all available ACP agents on the system.

  Probes each known agent's command for filesystem presence,
  merges with user-configured agents, and caches results.
  """
  @spec discover_all() :: [agent_entry()]
  def discover_all do
    init()

    configured = configured_agents()

    built_in =
      @known_agents
      |> Enum.filter(fn entry -> probe_command(entry.command) end)
      |> Enum.reject(fn entry ->
        Enum.any?(configured, fn c -> c.name == entry.name end)
      end)

    extra =
      configured
      |> Enum.filter(fn entry -> probe_command(entry.command) end)

    discovered = built_in ++ extra

    cache_results(discovered)

    discovered
  end

  @doc "Discover agents and register them in the Protocol.Registry."
  @spec discover_and_register() :: [atom()]
  def discover_and_register do
    discovered = discover_all()

    Enum.each(discovered, fn entry ->
      name = {:acp, entry.name}

      if not registered?(name) do
        try do
          AgentEx.Protocol.Registry.register(name, AgentEx.Protocol.ACP)
          Logger.debug("ACP agent discovered and registered: #{entry.display}")
        rescue
          _ -> :ok
        end
      end

      entry.aliases
      |> Enum.each(fn alias_name ->
        alias_key = {:acp, alias_name}

        if not registered?(alias_key) do
          try do
            AgentEx.Protocol.Registry.register(alias_key, AgentEx.Protocol.ACP)
          rescue
            _ -> :ok
          end
        end
      end)
    end)

    Enum.map(discovered, & &1.name)
  end

  @doc "Check if a specific agent is available."
  @spec available?(atom()) :: boolean()
  def available?(name) do
    case lookup(name) do
      nil -> false
      entry -> probe_command(entry.command)
    end
  end

  @doc "Look up an agent entry by name."
  @spec lookup(atom()) :: agent_entry() | nil
  def lookup(name) do
    case :ets.lookup(@table, {:agent, name}) do
      [{_, entry}] -> entry
      [] -> nil
    end
  end

  @doc "Get the launch command and args for a named agent."
  @spec launch_command(atom()) :: {String.t(), [String.t()]} | nil
  def launch_command(name) do
    case lookup(name) do
      nil -> nil
      entry -> {entry.command, entry.args}
    end
  end

  @doc "Get backend config for a named agent."
  @spec backend_config(atom(), keyword()) :: map()
  def backend_config(name, opts \\ []) do
    case lookup(name) do
      nil ->
        %{}

      entry ->
        %{
          command: entry.command,
          args: entry.args,
          workspace: Keyword.get(opts, :workspace, File.cwd!()),
          permission_policy: Keyword.get(opts, :permission_policy, :ask),
          mcp_servers: Keyword.get(opts, :mcp_servers, []),
          env: Keyword.get(opts, :env, %{})
        }
    end
  end

  @doc "Clear the discovery cache."
  @spec clear_cache() :: :ok
  def clear_cache do
    init()
    :ets.delete_all_objects(@table)
    :ok
  end

  # --- Private ---

  defp probe_command(command) do
    System.find_executable(command) != nil
  end

  defp registered?(name) do
    case AgentEx.Protocol.Registry.lookup(name) do
      {:ok, _} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  @doc "Parse configured agents from app config and ACP_AGENTS env var."
  @spec configured_agents() :: [agent_entry()]
  def configured_agents do
    app_config = Application.get_env(:agent_ex, :acp_agents, [])

    env_config =
      case System.get_env("ACP_AGENTS") do
        nil ->
          []

        agents_str ->
          agents_str
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.filter(&(&1 != ""))
          |> Enum.map(fn agent_str ->
            [name | rest] = String.split(agent_str, ~r/\s+/, parts: 2)

            %{
              name: String.to_atom(name),
              command: name,
              args: if(rest != [], do: String.split(hd(rest), ~r/\s+/), else: ["acp"]),
              display: name,
              aliases: [],
              cache_dirs: []
            }
          end)
      end

    Enum.map(app_config ++ env_config, fn
      entry when is_map(entry) ->
        %{
          name: entry[:name] || entry["name"] || :unknown,
          command: entry[:command] || entry["command"] || "unknown",
          args: entry[:args] || entry["args"] || ["acp"],
          display:
            entry[:display] || entry["display"] || to_string(entry[:name] || entry["name"]),
          aliases: entry[:aliases] || entry["aliases"] || [],
          cache_dirs: entry[:cache_dirs] || entry["cache_dirs"] || []
        }

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp cache_results(entries) do
    Enum.each(entries, fn entry ->
      :ets.insert(@table, {{:agent, entry.name}, entry})

      Enum.each(entry.aliases, fn alias_name ->
        :ets.insert(@table, {{:agent, alias_name}, entry})
      end)
    end)
  end
end
