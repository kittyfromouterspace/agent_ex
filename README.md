# Agentic

[![Elixir Version](https://img.shields.io/badge/Elixir-~%201.19-blue.svg)](https://elixir-lang.org/)
[![License](https://img.shields.io/badge/License-BSD--3--Clause-green.svg)](LICENSE)
[![Package](https://img.shields.io/badge/Package-Hex.pm-orange.svg)](https://hex.pm/packages/agentic)

A composable AI agent runtime for Elixir. Provides a complete agent loop with skills, working memory, knowledge persistence, and tool use. Drop it into any Elixir project to get a fully functional AI agent.

## Features

- **Composable Pipeline** — Middleware-style stage pipeline lets you mix and match agent behaviors
- **Multiple Profiles** — Eight built-in profiles: `agentic`, `agentic_planned`, `turn_by_turn`, `conversational`, `claude_code`, `opencode`, `codex`, `acp`
- **Tool Execution** — Built-in file operations, bash, subagent delegation, and extensibility for custom tools
- **Tool Activation** — Lazy tool discovery and activation with budget-limited promotion to first-class tools
- **Skills System** — YAML-defined skills that extend agent capabilities at runtime
- **Working Memory** — Context keeper with fact extraction and commitment detection
- **Persistence** — Transcript, plan, and knowledge persistence with pluggable backends
- **Model Router** — Manual tier-based or automatic analysis-based model selection
- **Strategy Layer** — Pluggable orchestration strategies that control run preparation and rerun decisions
- **Subagent Delegation** — Bounded subagent spawning for parallelizable tasks
- **Protocol System** — Pluggable agent protocols (LLM API, Claude Code CLI, OpenCode CLI, ACP)
- **Cost Controls** — Per-session cost limits, token usage tracking, and circuit breakers
- **Context Compression** — Two-tier compression (truncation + LLM summarization) for long conversations
- **Telemetry** — Full event instrumentation via Telemetry

## Installation

Add Agentic to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:agentic, "~> 0.2.0"}
  ]
end
```

### Database Backend

Agentic uses Recollect for knowledge persistence. Recollect supports two database backends:

**Option A: libSQL (Recommended for new projects)**
Single-file SQLite with native vector support. Zero configuration.

```elixir
def deps do
  [
    {:agentic, "~> 0.2.0"},
    {:ecto_libsql, "~> 0.9"}
  ]
end
```

Configure Recollect:
```elixir
config :recollect,
  database_adapter: Recollect.DatabaseAdapter.LibSQL,
  repo: MyApp.Repo,
  embedding: [
    provider: Recollect.Embedding.OpenRouter,
    dimensions: 768
  ]
```

**Option B: PostgreSQL (For existing installations)**
Traditional server-based database with pgvector extension.

```elixir
def deps do
  [
    {:agentic, "~> 0.2.0"},
    {:postgrex, "~> 0.19"},
    {:pgvector, "~> 0.3"}
  ]
end
```

Configure Recollect:
```elixir
config :recollect,
  database_adapter: Recollect.DatabaseAdapter.Postgres,
  repo: MyApp.Repo,
  embedding: [
    provider: Recollect.Embedding.OpenRouter,
    dimensions: 1536
  ]
```

## Quick Start

```elixir
result = Agentic.run(
  prompt: "Create a README.md file for my project",
  workspace: "/path/to/your/project",
  callbacks: %{
    llm_chat: fn params -> MyLLM.chat(params) end
  }
)

{:ok, %{text: response, cost: 0.05, tokens: 150, steps: 3}}
```

Resume a previous session:

```elixir
{:ok, result} = Agentic.resume(
  session_id: "agx-...",
  workspace: "/path/to/your/project",
  callbacks: %{llm_chat: &my_llm/1}
)
```

Scaffold a new workspace:

```elixir
:ok = Agentic.new_workspace("/path/to/new/project")
```

## Architecture

Agentic uses a **stage pipeline** architecture. Each stage wraps the next, receiving the context and a `next` function to call downstream.

The loop does not use a step counter. `ModeRouter` decides loop/terminate/compact based on the `(mode, phase, stop_reason)` triple. `max_turns` is a safety rail only.

- **Engine** builds the pipeline from stage modules
- **Profile** maps named profiles to stage lists and configuration
- **Phase** is a pure-function state machine with validated transitions
- **Context** is the loop state passed through every stage

### Agentic Profile Pipeline

```
ContextGuard → ProgressInjector → LLMCall → ModeRouter → TranscriptRecorder → ToolExecutor → CommitmentGate
```

### Profiles

| Profile | Behavior |
|---------|----------|
| `:agentic` | Full pipeline with tool use, progress tracking, context management (default) |
| `:agentic_planned` | Two-phase: plan → execute with tracking and verification |
| `:turn_by_turn` | LLM proposes changes, human approves before execution |
| `:conversational` | Simple call-respond, no tools |
| `:claude_code` | Claude Code CLI agent via local agent protocol |
| `:opencode` | OpenCode CLI agent via local agent protocol |
| `:codex` | Codex CLI agent via local agent protocol |
| `:acp` | Agent Client Protocol (JSON-RPC 2.0 over stdio) |

## Callbacks API

The `callbacks` map connects Agentic to your LLM provider and external systems:

### Required

- `:llm_chat` — `(params) -> {:ok, response} | {:error, term}`

### Optional

- `:execute_tool` — custom tool handler (defaults to built-in tools)
- `:on_event` — `(event, ctx) -> :ok` for UI streaming
- `:on_response_facts` — `(ctx, text) -> :ok` for custom fact processing
- `:on_tool_facts` — `(ws_id, name, result, turn) -> :ok`
- `:on_persist_turn` — `(ctx, text) -> :ok`
- `:get_tool_schema` — `(name) -> {:ok, schema} | {:error, reason}`
- `:get_secret` — `(service, key) -> {:ok, value} | {:error, reason}`
- `:knowledge_search` — `(query, opts) -> {:ok, entries} | {:error, term}`
- `:knowledge_create` — `(params) -> {:ok, entry} | {:error, term}`
- `:knowledge_recent` — `(scope_id) -> {:ok, entries} | {:error, term}`
- `:search_tools` — `(query, opts) -> [result]`
- `:execute_external_tool` — `(name, args, ctx) -> {:ok, result} | {:error, reason}`

## Core Tools

Agentic ships with built-in tools:

### File Operations

- `read_file` — Read file contents with optional line range
- `write_file` — Create or overwrite files
- `edit_file` — Apply targeted edits by exact text match
- `list_files` — Find files by glob pattern
- `bash` — Execute shell commands in the workspace

### Delegation

- `delegate_task` — Delegate to bounded subagents for parallelizable work

### Skills

- `skill_list` — List installed skills
- `skill_read` — Read skill instructions
- `skill_search` — Search for skills from public registries
- `skill_info` — Fetch detailed info about a skill before installing
- `skill_install` — Install a skill from GitHub
- `skill_remove` — Remove an installed skill
- `skill_analyze` — Analyze a skill's model tier requirements

### Memory

- `memory_query` — Search the knowledge store
- `memory_write` — Persist content to the knowledge store
- `memory_note` — Store key-value pairs in fast in-process working memory
- `memory_recall` — Search in-process working memory

### Tool Gateway

- `search_tools` — Discover available external tools
- `use_tool` — Execute an external tool (MCP, OpenAPI, integration)
- `get_tool_schema` — Get the full input schema for an external tool
- `activate_tool` — Promote an external tool to first-class status
- `deactivate_tool` — Remove an activated tool

Extend via the skills system, tool activation, or custom callbacks.

## Storage Backends

- **Transcript** — Session history with event streaming
- **Plan** — Structured task plans (for `:agentic_planned` mode)
- **Knowledge** — Persistent fact storage with search (`:local` file-based or `:recollect` graph)
- **Context** — Workspace context with pluggable backends

All backends have a `:local` file-based implementation.

## Configuration

```elixir
Agentic.run(
  prompt: "...",
  workspace: "/path",
  callbacks: %{llm_chat: &my_llm/1},
  profile: :agentic,              # which profile to use
  mode: :agentic,                 # shorthand for profile
  system_prompt: "...",           # custom system prompt
  history: [...],                 # prior messages
  model_tier: :primary,           # which model tier to use (manual mode)
  model_selection_mode: :manual,  # :manual (tier-based) or :auto (analysis-based)
  model_preference: :optimize_price, # :optimize_price or :optimize_speed (auto mode)
  model_filter: nil,              # :free_only or nil (auto mode)
  strategy: :default,             # orchestration strategy
  strategy_opts: [],              # extra opts for strategy init
  cost_limit: 5.0,               # per-session cost limit in USD
  session_id: "agx-...",          # custom session ID
  user_id: "user-123",            # for API key resolution
  plan: %{...}                    # pre-built plan (for agentic_planned)
)
```

## Development

```bash
mix deps.get          # Install dependencies
mix setup             # Setup database
mix test             # Run tests
mix format           # Format code
mix dialyzer         # Type check
```

## License

BSD-3-Clause — See [LICENSE](LICENSE) for details.

## Contributing

Contributions welcome. Please ensure tests pass and dialyzer is clean before submitting PRs.