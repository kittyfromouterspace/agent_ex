# ACP Integration Spec: Agent Client Protocol for AgentEx

## Status: IN PROGRESS

## Implementation Progress

### Phase 1: ACP Client Core -- COMPLETE
- [x] `AgentEx.Protocol.ACP.Types` -- type definitions and conversions
- [x] `AgentEx.Protocol.ACP.Client` -- JSON-RPC 2.0 stdio client with listener
- [x] `AgentEx.Protocol.ACP.Session` -- initialize/authenticate/session lifecycle
- [x] `AgentEx.Protocol.ACP.Permission` -- bridge ACP permissions to AgentEx
- [x] `AgentEx.Protocol.ACP` -- AgentProtocol behaviour implementation
- [x] `AgentEx.Loop.Stages.ACPExecutor` -- ACP-specific executor stage
- [x] Add `:acp` transport type to `AgentEx.Protocol`
- [x] Allow tuple keys in `Protocol.Registry`
- [x] ACP profile in `AgentEx.Loop.Profile`
- [x] Application startup registration with config-driven agents

### Phase 2: Discovery & Agent Quirks -- IN PROGRESS
- [x] `AgentEx.Protocol.ACP.Discovery` -- 15-agent known DB + config + env var
- [x] `AgentEx.Protocol.ACP.Quirks` -- agent-specific workarounds (from acpx)
- [ ] ACP-specific telemetry events
- [ ] Integration test with mock subprocess

### Tests -- IN PROGRESS
- [x] `test/agent_ex/protocol/acp/types_test.exs` -- 15 tests
- [x] `test/agent_ex/protocol/acp/permission_test.exs` -- 11 tests
- [x] `test/agent_ex/protocol/acp/discovery_test.exs` -- 8 tests
- [x] `test/agent_ex/protocol/acp/quirks_test.exs` -- 16 tests
- [ ] `test/agent_ex/protocol/acp/client_test.exs` -- mock subprocess tests
- [ ] `test/agent_ex/protocol/acp/session_test.exs` -- mock session tests

### Files Changed/Created
```
lib/agent_ex/protocol.ex                          -- added :acp transport
lib/agent_ex/protocol/registry.ex                  -- tuple key support
lib/agent_ex/protocol/acp.ex                       -- NEW: main ACP protocol
lib/agent_ex/protocol/acp/types.ex                  -- NEW: type definitions
lib/agent_ex/protocol/acp/client.ex                 -- NEW: JSON-RPC client
lib/agent_ex/protocol/acp/session.ex               -- NEW: session lifecycle
lib/agent_ex/protocol/acp/permission.ex            -- NEW: permission bridge
lib/agent_ex/protocol/acp/discovery.ex             -- NEW: agent discovery
lib/agent_ex/protocol/acp/quirks.ex                -- NEW: agent-specific quirks
lib/agent_ex/loop/stages/acp_executor.ex           -- NEW: ACP executor stage
lib/agent_ex/loop/profile.ex                       -- added ACP profile
lib/agent_ex/application.ex                       -- ACP registration
test/agent_ex/protocol/acp/types_test.exs           -- NEW
test/agent_ex/protocol/acp/permission_test.exs     -- NEW
test/agent_ex/protocol/acp/discovery_test.exs      -- NEW
test/agent_ex/protocol/acp/quirks_test.exs         -- NEW
docs/acp-integration-spec.md                       -- this file
```

### Key Design Insights from acpx
The acpx codebase (https://github.com/openclaw/acpx) was studied in depth and influenced:
- Agent registry with 15+ agents and exact launch commands
- Agent-specific quirks (Gemini version detection, Copilot pre-flight, Qoder extra args, Claude timeouts)
- Permission mode hierarchy (deny-all < approve-reads < approve-all)
- Tool kind inference from titles when agents don't provide one
- Error normalization patterns

## 1. Background & Problem Statement

AgentEx currently supports three CLI-based local agent protocols (Claude Code, OpenCode, Codex), each implemented as a bespoke module with its own wire format, parsing logic, and session management. Adding a new agent requires writing a new protocol module from scratch.

Meanwhile, the **Agent Client Protocol (ACP)** -- https://agentclientprotocol.com -- has emerged as a standard for editor-to-agent communication. **30+ coding agents now implement ACP**, including:

- Kimi CLI (`kimi acp`)
- Claude Agent, Codex CLI, Cursor
- Gemini CLI, GitHub Copilot CLI
- Goose, OpenHands, Cline
- Qwen Code, Mistral Vibe, Kiro CLI
- And many more

Every ACP agent speaks the same **JSON-RPC 2.0 over stdio** wire protocol with the same methods (`initialize`, `session/new`, `session/prompt`, `session/update`, `session/cancel`). This means we can write **one ACP client implementation** and immediately support 30+ agents.

### Why not the IBM/BeeAI "Agent Communication Protocol"?

There are two protocols abbreviated "ACP":

| | Agent Client Protocol | Agent Communication Protocol |
|---|---|---|
| URL | agentclientprotocol.com | agentcommunicationprotocol.dev |
| Origin | Zed / coding agent ecosystem | IBM / BeeAI |
| Wire format | JSON-RPC 2.0 over stdio | REST over HTTP |
| Use case | Editor <-> coding agent | Agent <-> agent orchestration |
| Transport | Local subprocess (primary) | HTTP server |
| Status | Active, growing rapidly | Merged into A2A, archived |

**Kimi CLI and every coding agent listed above implements the Agent Client Protocol (JSON-RPC over stdio).** The IBM REST-based protocol is the wrong target. This spec addresses the correct one.

## 2. ACP Protocol Summary

### Transport
- **stdio**: Client launches agent as subprocess. JSON-RPC messages over stdin/stdout, newline-delimited, no embedded newlines.
- **Streamable HTTP**: Draft proposal, not yet stable.

### Lifecycle

```
Client                    Agent
  |--- initialize -------->|
  |<-- initialize resp -----|
  |--- authenticate ------->|  (if required)
  |<-- auth resp -----------|
  |--- session/new -------->|
  |<-- {sessionId} ---------|
  |--- session/prompt ----->|
  |<-- session/update (streaming) ----|  (notifications, no response)
  |<-- session/request_permission -->|  (agent asks client)
  |-- permission response ------------>|
  |<-- session/prompt response -------|  (stopReason)
  |--- session/cancel ----->|  (notification, no response)
```

### Key Methods

| Method | Direction | Description |
|---|---|---|
| `initialize` | C->A | Negotiate protocol version, exchange capabilities |
| `authenticate` | C->A | Authenticate if agent requires it |
| `session/new` | C->A | Create new session, returns `sessionId` |
| `session/load` | C->A | Resume existing session (if `loadSession` capability) |
| `session/prompt` | C->A | Send user message, returns when turn completes |
| `session/update` | A->C | Notification: streaming chunks, tool calls, plans |
| `session/cancel` | C->A | Notification: cancel current prompt turn |
| `session/request_permission` | A->C | Agent requests user authorization for tool call |
| `session/set_mode` | C->A | Switch agent operating mode |
| `session/list` | C->A | List known sessions (if `sessionCapabilities.list`) |

### Key Types

**ContentBlock** (shared with MCP):
- `text` -- plain text
- `image` -- base64-encoded image
- `audio` -- base64-encoded audio
- `resource` -- embedded file/resource content
- `resource_link` -- URI reference to resource

**SessionUpdate** variants:
- `agent_message_chunk` -- streaming text from agent
- `user_message_chunk` -- replayed user message
- `tool_call` -- new tool invocation
- `tool_call_update` -- tool progress update
- `plan` -- agent execution plan

**StopReason**: `end_turn`, `max_tokens`, `max_turn_requests`, `refusal`, `cancelled`

**ToolCallContent**:
- `content` -- standard content blocks
- `diff` -- file modification diff
- `terminal` -- live terminal output

## 3. Kimi CLI ACP Integration Assessment

### How Kimi CLI maps to ACP

| Aspect | Kimi CLI | ACP Spec | Mapping Quality |
|---|---|---|---|
| **Launch command** | `kimi acp` | Subprocess with args | Perfect match |
| **Transport** | stdin/stdout, newline-delimited JSON-RPC | stdio transport | Perfect match |
| **Initialization** | Negotiates protocol version, exchanges capabilities | `initialize` method | Perfect match |
| **Authentication** | Returns `AUTH_REQUIRED` (code -32000) if not logged in, client must guide user to `kimi login` | `authenticate` method + `authMethods` from initialize | Perfect match |
| **Session creation** | `session/new` with `cwd` and `mcpServers` | Standard ACP | Perfect match |
| **Session loading** | Supports `--continue` and `--session` flags; `loadSession` capability | `session/load` | Good -- ACP maps CLI flags to protocol methods |
| **Prompt turns** | `session/prompt` with `ContentBlock[]` | Standard ACP | Perfect match |
| **Streaming** | `session/update` notifications for chunks, tool calls, plans | Standard ACP | Perfect match |
| **Tool calls** | Reports via `session/update` with `tool_call` and `tool_call_update` | Standard ACP | Perfect match |
| **Permission requests** | Agent can ask client for approval before operations | `session/request_permission` | Perfect match |
| **Cancellation** | Client sends `session/cancel` notification | Standard ACP | Perfect match |
| **Multi-session** | Supports multiple concurrent sessions | Standard ACP | Perfect match |
| **MCP integration** | Agent can connect to client-provided MCP servers | Standard ACP | Perfect match |
| **File system** | Agent can request file reads/writes via client | `fs/read_text_file`, `fs/write_text_file` | Perfect match |
| **Terminal** | Agent can create terminals via client | `terminal/create` etc. | Perfect match |
| **Image input** | Supports `Ctrl-V` paste, `image_in` model capability | `promptCapabilities.image` | Perfect match |
| **Thinking mode** | `--thinking` flag, some models always think | No direct ACP mapping | ACP doesn't standardize thinking mode; handled via agent-side config or `session/set_mode` |

### Gaps and Considerations

1. **Thinking mode**: ACP doesn't have a standard way to toggle thinking. Kimi handles this internally. We can pass it as a `session/set_mode` or via custom `_meta` fields.

2. **Yolo mode**: Kimi's `--yolo` / `/yolo` auto-approve mode. In ACP, this maps to the client always returning `allow_always` for `session/request_permission`. AgentEx can configure this behavior.

3. **Slash commands**: Kimi has `/login`, `/clear`, `/compact`, `/sessions`, etc. ACP has `AvailableCommandsUpdate` for advertising slash commands to the client. We should surface these.

4. **Session persistence**: Kimi auto-saves sessions with state (approval decisions, subagents, directories). ACP's `session/load` handles the resume path.

5. **Context compaction**: Kimi's `/compact` maps to an internal agent concern -- ACP doesn't standardize this. The agent manages it internally.

**Conclusion: Kimi CLI is a textbook ACP implementation. The mapping is near-perfect.**

## 4. Design

### 4.1 Architecture

```
                           AgentEx
                             |
                    +--------+--------+
                    |  Protocol Registry|
                    +--------+--------+
                             |
                    +--------+--------+
                    | AgentEx.Protocol |
                    |      .ACP       |  <-- NEW: generic ACP client
                    +--------+--------+
                             |
              +--------------+--------------+
              |                             |
    +---------+---------+       +---------+---------+
    | ACP Client         |       | ACP Discovery     |
    | (JSON-RPC/stdio)   |       | (auto-detect)     |
    +-------------------+       +-------------------+
              |
    +---------+---------+
    | kimi acp (Port)   |       30+ other ACP agents
    | claude (Port)     |       discovered dynamically
    | cursor (Port)     |
    +-------------------+
```

### 4.2 New Transport Type: `:acp`

Add `:acp` to `AgentEx.Protocol.transport_type/0`. This is semantically distinct from `:local_agent` -- while ACP agents run locally, the protocol is standardized rather than bespoke.

### 4.3 File Structure

```
lib/agent_ex/
  protocol/
    acp.ex                    # Generic ACP protocol (implements AgentProtocol)
    acp/
      client.ex               # JSON-RPC 2.0 client over stdio
      discovery.ex            # Auto-discovery of ACP-capable CLIs
      session.ex              # Session lifecycle management
      types.ex                # ACP type definitions (ContentBlock, etc.)
      permission.ex           # Permission request handling
      manifest.ex             # Agent capability manifest from initialize
      cache.ex                # ETS cache for discovery results
```

### 4.4 Core Modules

#### `AgentEx.Protocol.ACP` (implements `AgentEx.AgentProtocol`)

One module that can talk to **any** ACP agent. The agent identity (kimi, cursor, etc.) is a parameter, not a separate module.

```elixir
# Key config
%{
  command: "kimi",           # CLI binary
  args: ["acp"],             # ACP mode args
  env: %{},                  # Extra env vars
  workspace: "/path/to/dir", # Working directory (cwd)
  mcp_servers: [],           # MCP servers to forward
  permission_policy: :ask    # :ask | :allow_all | :deny_all
}
```

Maps `AgentProtocol` callbacks to ACP methods:

| AgentProtocol callback | ACP method |
|---|---|
| `start/2` | Launch subprocess, send `initialize`, optionally `authenticate`, send `session/new` |
| `send/3` | Send `session/prompt`, collect `session/update` notifications until response |
| `resume/3` | Send `session/load` (if supported), then `session/prompt` |
| `stop/1` | Send `session/cancel` if active, close stdin, terminate subprocess |
| `available?/0` | Check `System.find_executable(command)` |
| `transport_type/0` | `:acp` |

#### `AgentEx.Protocol.ACP.Client` -- JSON-RPC 2.0 over stdio

Low-level JSON-RPC client. Handles:

- Message framing (newline-delimited JSON)
- Request/response correlation via `id` field
- Notification handling (no `id`, no response expected)
- Bidirectional requests (agent can call client methods like `session/request_permission`)
- Timeout management

Key difference from existing CLI protocols: **bidirectional**. The agent can call methods on the client (permission requests, file reads, terminal creation). This requires a listener loop running alongside the request/response flow.

```elixir
defmodule AgentEx.Protocol.ACP.Client do
  defstruct [:port, :request_id, :pending_requests, :notification_handler]

  def start_link(command, args, env, opts \\ [])
  def send_request(client, method, params)       # -> {:ok, result} | {:error, reason}
  def send_notification(client, method, params)  # -> :ok
  def on_notification(client, handler)            # -> :ok
  def close(client)                               # -> :ok
end
```

#### `AgentEx.Protocol.ACP.Discovery` -- Auto-detect ACP agents

Probes the system for ACP-capable CLIs:

**Known agents database** (bundled, updatable):
```elixir
@known_agents [
  %{name: :kimi, command: "kimi", args: ["acp"], display: "Kimi Code"},
  %{name: :claude, command: "claude", args: ["acp"], display: "Claude Agent"},
  %{name: :cursor, command: "cursor", args: ["acp"], display: "Cursor"},
  %{name: :gemini, command: "gemini", args: ["cli", "acp"], display: "Gemini CLI"},
  %{name: :copilot, command: "gh", args: ["copilot", "acp"], display: "GitHub Copilot"},
  %{name: :codex, command: "codex", args: ["acp"], display: "Codex CLI"},
  %{name: :opencode, command: "opencode", args: ["--acp"], display: "OpenCode"},
  %{name: :goose, command: "goose", args: ["acp"], display: "Goose"},
  %{name: :cline, command: "cline", args: ["acp"], display: "Cline"},
  %{name: :qwen, command: "qwen-code", args: ["acp"], display: "Qwen Code"},
  # ... extensible via config
]
```

**Discovery flow:**
1. Check `config.exs` for `acp_agents` list (user can add custom entries)
2. Check `ACP_AGENTS` env var
3. For each known agent: `System.find_executable(command)` -- if found, probe with `command --version` or attempt `initialize` handshake
4. Cache results in ETS with 5-minute TTL
5. Register discovered agents in `Protocol.Registry` as `{:acp, agent_name}`

**Result**: Any ACP-compatible CLI installed on the system is automatically available. No per-agent protocol modules needed.

#### `AgentEx.Protocol.ACP.Session` -- Session lifecycle

Wraps the ACP session flow:

```elixir
def init(agent_config, client_capabilities, workspace) do
  # 1. initialize
  # 2. authenticate (if needed)
  # 3. session/new or session/load
  # Returns {:ok, session} with agent_capabilities, session_id
end

def prompt(session, content_blocks) do
  # Send session/prompt, stream session/update notifications
  # Handle permission requests from agent
  # Return when prompt response received (stopReason)
end

def cancel(session) do
  # Send session/cancel notification
end
```

#### `AgentEx.Protocol.ACP.Permission` -- Permission handling

Bridges ACP `session/request_permission` to AgentEx's tool permission system:

```elixir
def handle_request(session, permission_request, ctx) do
  case ctx.tool_permissions do
    %{auto: :approve} -> respond_allow(session, request)
    %{auto: :deny} -> respond_deny(session, request)
    _ -> delegate_to_callback(session, request, ctx)
  end
end
```

Maps ACP permission option kinds to AgentEx concepts:
- `allow_once` -> `:auto` for this call
- `allow_always` -> update `tool_permissions` map
- `reject_once` -> deny this call
- `reject_always` -> deny and cache

#### `AgentEx.Protocol.ACP.Types` -- ACP type definitions

Shared type specs for ACP protocol types:
- `ContentBlock` (text, image, audio, resource, resource_link)
- `SessionUpdate` variants
- `ToolCallUpdate` with status and content
- `StopReason`
- `AgentCapabilities`, `ClientCapabilities`
- `PermissionOption`, `RequestPermissionOutcome`

Also provides conversion functions:
- `to_agentex_messages/1` -- ACP ContentBlock[] -> AgentEx message format
- `from_agentex_messages/1` -- AgentEx messages -> ACP ContentBlock[]
- `tool_calls_to_pending/1` -- ACP tool_call updates -> AgentEx pending_tool_calls

### 4.5 Bidirectional Communication Architecture

ACP is fundamentally bidirectional. The agent can call methods on the client. This is different from existing CLI protocols where communication is unidirectional (we send, they respond).

```
AgentEx (Client)                    ACP Agent (subprocess)
       |                                      |
       |--- initialize ---------------------->|
       |<-- initialize resp ------------------|
       |                                      |
       |--- session/new --------------------->|
       |<-- sessionId ------------------------|
       |                                      |
       |--- session/prompt ------------------>|
       |                                      |
       |<-- session/update (chunk) -----------|  notification
       |<-- session/update (chunk) -----------|  notification
       |<-- session/update (tool_call) -------|  notification
       |<-- session/request_permission ----->|  REQUEST from agent
       |--- permission response ------------>|  RESPONSE from client
       |                                      |
       |<-- session/update (tool_update) -----|  notification
       |<-- session/prompt response ---------|  response to original request
```

Implementation: A dedicated listener process receives all messages from the agent's stdout. It routes responses to waiting request callers via a `Registry`, and delivers notifications to a configured handler callback.

```elixir
defmodule AgentEx.Protocol.ACP.ClientListener do
  use GenServer

  # Receives all stdout from the ACP agent process
  # Routes responses (has "id") to callers via Registry
  # Delivers notifications (no "id") to notification handler
  # Handles bidirectional requests (agent calling client methods)
end
```

### 4.6 Client Capabilities

When AgentEx acts as an ACP client, it should advertise these capabilities:

```elixir
%{
  protocolVersion: 1,
  clientCapabilities: %{
    fs: %{
      readTextFile: true,
      writeTextFile: true
    },
    terminal: true
  },
  clientInfo: %{
    name: "agent_ex",
    title: "AgentEx",
    version: AgentEx.version()
  }
}
```

This means AgentEx needs to implement the **Client side** of ACP too:
- `fs/read_text_file` -- map to AgentEx workspace file reading
- `fs/write_text_file` -- map to AgentEx workspace file writing
- `terminal/create` -- map to AgentEx's bash execution capability

These can delegate to existing AgentEx tool infrastructure via callbacks.

### 4.7 Profile Integration

No new profiles needed. Instead, any existing profile can use an ACP agent by setting the protocol:

```elixir
# Use Kimi via ACP with the agentic profile
AgentEx.run(prompt, workspace: "/path",
  profile: :agentic,
  protocol: {:acp, :kimi}
)

# Use Claude Agent via ACP
AgentEx.run(prompt, workspace: "/path",
  profile: :agentic,
  protocol: {:acp, :claude}
)
```

The `CLIExecutor` stage already handles `transport_type: :local_agent`. We extend it to also handle `:acp`, or create an `ACPExecutor` stage that mirrors CLIExecutor but uses the ACP client.

### 4.8 Configuration

```elixir
# config/config.exs
config :agent_ex, :acp,
  # Known ACP agents (appended to built-in list)
  agents: [
    %{name: :my_custom_agent, command: "my-agent", args: ["--acp"], display: "My Agent"}
  ],
  # Default permission policy
  permission_policy: :ask,
  # Auto-discover on startup
  discover_on_start: true,
  # Client capabilities to advertise
  client_capabilities: %{
    fs: %{readTextFile: true, writeTextFile: true},
    terminal: true
  }
```

### 4.9 Registry Changes

Current registry uses atom keys. ACP agents use tuple keys `{:acp, agent_name}`:

```elixir
# Register discovered ACP agents
AgentEx.Protocol.Registry.register({:acp, :kimi}, AgentEx.Protocol.ACP)

# Lookup
{:ok, module} = AgentEx.Protocol.Registry.lookup({:acp, :kimi})
# -> {:ok, AgentEx.Protocol.ACP}  (same module for all ACP agents)

# List all ACP agents
AgentEx.Protocol.Registry.for_transport(:acp)
# -> [{:acp, :kimi}, {:acp, :claude}, {:acp, :cursor}, ...]
```

The registry needs a small change: allow tuple keys. Currently it uses `is_atom(name)` guard. This is a one-line change.

### 4.10 Discovery-to-Profile Bridge

For convenience, auto-discovered agents get synthetic profiles:

```elixir
# After discovering kimi, auto-create:
AgentEx.Loop.Profile.put(:kimi_acp, %{
  stages: AgentEx.Loop.Profile.stages(:claude_code),  # reuse CLI pipeline
  config: %{
    max_turns: 50,
    protocol: {:acp, :kimi},
    transport_type: :acp,
    cli_config: %{command: "kimi", args: ["acp"]}
  }
})
```

This means users can do:
```elixir
AgentEx.run(prompt, workspace: "/path", profile: :kimi_acp)
```

## 5. Migration Path for Existing CLI Protocols

Claude Code, OpenCode, and Codex all support ACP (or will soon). Over time, we can deprecate the bespoke protocol modules and route everything through ACP:

```
Current state:           Target state:
ClaudeCode (bespoke) -> ACP (kimi, claude, cursor, ...)
OpenCode (bespoke)   -> ACP
Codex (bespoke)       -> ACP
```

This eliminates ~800 lines of near-identical subprocess management code.

## 6. Phased Implementation Plan

### Phase 1: ACP Client Core
- `AgentEx.Protocol.ACP.Types` -- type definitions and conversions
- `AgentEx.Protocol.ACP.Client` -- JSON-RPC 2.0 stdio client with listener
- `AgentEx.Protocol.ACP.Session` -- initialize/authenticate/session lifecycle
- `AgentEx.Protocol.ACP` -- AgentProtocol implementation
- Add `:acp` transport type to `AgentEx.Protocol`
- Allow tuple keys in `Protocol.Registry`

### Phase 2: Discovery & Auto-Registration
- `AgentEx.Protocol.ACP.Discovery` -- known agents DB + filesystem probing
- `AgentEx.Protocol.ACP.Cache` -- ETS cache for discovery
- `AgentEx.Protocol.ACP.Manifest` -- capability metadata from initialize
- Auto-register discovered agents on startup
- Synthetic profile generation for discovered agents

### Phase 3: Client Capabilities & Permission Handling
- `AgentEx.Protocol.ACP.Permission` -- bridge ACP permissions to AgentEx
- Implement `fs/read_text_file`, `fs/write_text_file` client methods
- Implement `terminal/create` client method
- `ACPExecutor` stage (or extend `CLIExecutor`)
- MCP server forwarding to ACP agents

### Phase 4: Consolidation
- Migrate Claude Code / OpenCode / Codex to ACP when their ACP support is stable
- Deprecate bespoke protocol modules
- Add ACP-specific telemetry events

## 7. Testing Strategy

- **Unit tests**: JSON-RPC message parsing, type conversions, permission handling
- **Integration tests**: Launch actual `kimi acp` (if installed), run initialize + session/new + prompt
- **Mock tests**: Mock subprocess with expected ACP responses for CI
- **Discovery tests**: Verify agent detection with stub binaries

## 8. Risks

| Risk | Mitigation |
|---|---|
| ACP spec is still evolving (v1, draft proposals for HTTP transport) | Pin to stable v1 methods only. Gate experimental features behind capability checks. |
| Bidirectional communication adds complexity | Use a dedicated listener GenServer with clear routing. |
| Some agents have partial ACP implementations | Capability negotiation in `initialize` tells us exactly what's supported. |
| Permission handling may deadlock (agent waits for permission, client waits for response) | Time-bound permission requests. Default to `:allow_all` in agentic mode. |
| Discovery may be slow on startup with many agents | Parallel probing with short timeouts. Cache results. Lazy discovery (probe on first use). |
