# AgentEx Implementation Guide

## Overview

AgentEx is a composable AI agent runtime for Elixir (~1.19+). It provides a complete agent loop with skills, working memory, knowledge persistence, and tool execution. The library uses a middleware-style pipeline architecture where stages wrap each other to form the loop.

## Quick Start

```elixir
{:ok, result} = AgentEx.run(
  prompt: "Help me refactor this module",
  workspace: "/path/to/workspace",
  callbacks: %{
    llm_chat: fn params -> MyLLM.chat(params) end
  }
)

IO.inspect(result)
# => %{text: "...", cost: 0.05, tokens: 1500, steps: 3}
```

---

## Core Concepts

### The Agent Loop

The loop is built from **stages** — composable middleware functions. Each stage receives the context and a `next` function to call the rest of the pipeline.

```
┌─────────────────────────────────────────────────────────────┐
│                      Agent Loop                              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ContextGuard → ProgressInjector → LLMCall → ModeRouter   │
│       ↓                                    ↓               │
│  ToolExecutor ← TranscriptRecorder ← CommitmentGate       │
│                                                             │
│  (stages wrap each other right-to-left)                    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Profiles

AgentEx supports four execution profiles:

| Profile | Description | Phases |
|---------|-------------|--------|
| `:agentic` | Full tool-use loop | `execute` |
| `:agentic_planned` | Plan → Execute → Verify | `plan` → `execute` → `verify` |
| `:turn_by_turn` | Human-in-the-loop | `review` → `execute` |
| `:conversational` | Call-respond only | `execute` |

### Context

The `AgentEx.Loop.Context` struct threads through all stages:

- **Identity**: `session_id`, `user_id`, `caller`
- **State**: `messages`, `tools`, `phase`, `turns_used`
- **Tracking**: `total_cost`, `total_tokens`, `accumulated_text`
- **Config**: `max_turns`, `compaction_at_pct`, etc.
- **Callbacks**: All integration points

---

## API Reference

### AgentEx.run/1 — Main Entry Point

```elixir
AgentEx.run(
  prompt: "...",
  workspace: "/path/to/workspace",
  callbacks: %{
    llm_chat: fn params -> {:ok, response} end
  },
  # optional:
  system_prompt: "You are...",
  history: [%{"role" => "user", "content" => "..."}],
  profile: :agentic,
  mode: :agentic,
  model_tier: :primary,
  session_id: "session-123",
  user_id: "user-456",
  caller: self(),
  workspace_id: "ws-789",
  cost_limit: 5.0,
  plan: %{steps: [...]},
  tool_permissions: %{"bash" => :approve}
)
```

**Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `prompt` | string | **required** | User prompt |
| `workspace` | string | **required** | Workspace directory |
| `callbacks` | map | **required** | Callback functions |
| `system_prompt` | string | auto-generated | Override system prompt |
| `history` | list | `[]` | Prior conversation messages |
| `profile` | atom | `:agentic` | Pipeline profile to use |
| `mode` | atom | `:agentic` | Execution mode (overrides profile) |
| `model_tier` | atom | `:primary` | Model tier for LLM calls |
| `session_id` | string | auto-generated | Session identifier |
| `user_id` | string | nil | User identifier |
| `caller` | pid | `self()` | Process to receive events |
| `workspace_id` | string | nil | Workspace ID for context keeper |
| `cost_limit` | float | 5.0 | Per-session USD cost limit |
| `plan` | map | nil | Pre-built plan (agentic_planned mode) |
| `tool_permissions` | map | `{}` | Tool permission overrides |
| `model_routes` | list | nil | Fallback model routes for routing |

**Returns:** `{:ok, %{text: string, cost: float, tokens: integer, steps: integer}}` or `{:error, reason}`

---

### AgentEx.resume/1 — Session Recovery

```elixir
AgentEx.resume(
  session_id: "agx-abc123",
  workspace: "/path/to/workspace",
  callbacks: %{llm_chat: fn -> ... end},
  transcript_backend: AgentEx.Persistence.Transcript.Local
)
```

Loads a previous session transcript and continues from where it left off.

---

### AgentEx.new_workspace/2 — Workspace Scaffolding

```elixir
AgentEx.new_workspace("/path/to/new/workspace", 
  workspace_type: :general,  # :general, :personal, :admin, :team, :task
  storage: %AgentEx.Storage.Context{...}
)
```

Creates the standard workspace structure with AGENTS.md, MEMORY.md, TOOLS.md, etc.

---

## Callbacks

Callbacks connect AgentEx to your infrastructure.

### Required Callbacks

#### `:llm_chat`

```elixir
fn params -> 
  # params is a map with:
  #   "messages" => [...],
  #   "tools" => [...],
  #   "session_id" => "...",
  #   "user_id" => "...",
  #   "model_tier" => "primary",
  #   "cache_control" => %{"stable_hash" => "...", "prefix_changed" => true|false}
  #   "_route" => %{provider_name: "openrouter", model_id: "...", api_type: :openai_completions, ...} | nil
   
  {:ok, %{
    "content" => [%{"type" => "text", "text" => "..."}],
    "stop_reason" => "end_turn" | "tool_use" | "max_tokens",
    "usage" => %{"input_tokens" => 1000, "output_tokens" => 500},
    "cost" => 0.03
  }}
end
```

The LLM response **must** include:
- `"content"` — list of content blocks (text and/or tool_use)
- `"stop_reason"` — `"end_turn"`, `"tool_use"`, or `"max_tokens"`
- `"usage"` — token usage map (optional but recommended for cost tracking)
- `"cost"` — USD cost (optional)

### Optional Callbacks

| Callback | Signature | Purpose |
|----------|-----------|---------|
| `:execute_tool` | `(name, input, ctx) -> {:ok, result}` | Custom tool executor |
| `:on_event` | `(event, ctx) -> :ok` | UI/event streaming |
| `:on_response_facts` | `(ctx, text) -> :ok` | Extract facts from responses |
| `:on_tool_facts` | `(ws_id, name, result, turn) -> :ok` | Extract facts from tool results |
| `:on_persist_turn` | `(ctx, text) -> :ok` | Persist turn to transcript |
| `:on_plan_created` | `(plan, ctx) -> {:ok, ctx} | {:revise, feedback, ctx}` | Validate/approve plan |
| `:on_tool_approval` | `(name, input, ctx) -> :approved | :denied` | Human approval for tools |
| `:get_tool_schema` | `(name) -> {:ok, schema}` | Dynamic tool schema |
| `:get_secret` | `(service, key) -> {:ok, value}` | Secret retrieval |
| `:knowledge_search` | `(query, opts) -> {:ok, entries}` | Knowledge retrieval |
| `:knowledge_create` | `(params) -> {:ok, entry}` | Knowledge creation |
| `:knowledge_recent` | `(scope_id) -> {:ok, entries}` | Recent knowledge |
| `:search_tools` | `(query, opts) -> [result]` | Tool discovery |
| `:execute_external_tool` | `(name, args, ctx) -> {:ok, result}` | External tool execution |

---

## Built-in Tools

AgentEx provides core file and system tools:

| Tool | Input Schema | Description |
|------|--------------|-------------|
| `read_file` | `path`, `offset?`, `limit?` | Read file contents |
| `write_file` | `path`, `content` | Create or overwrite file |
| `edit_file` | `path`, `old_text`, `new_text` | Surgical text replacement |
| `bash` | `command`, `timeout?` | Execute shell command |
| `list_files` | `pattern?` | Glob file listing |
| `delegate_task` | `prompt`, `workspace`, `max_turns?` | Spawn subagent |

### Extension Tools

Additional tools are provided by extension modules:

- **Skill** — `skill_list`, `skill_read`, `skill_install`, `skill_remove`, `skill_search`, `skill_analyze`
- **Gateway** — `gateway_activate`, `gateway_deactivate`, `gateway_list`
- **Memory** — `memory_query`, `memory_write`, `context_get`

---

## Stages

Stages are the building blocks of the agent loop. Each implements `AgentEx.Loop.Stage` with `call(ctx, next)`.

### Core Stages

| Stage | Purpose |
|-------|---------|
| `ContextGuard` | Validates context before loop entry |
| `ProgressInjector` | Injects progress messages into system prompt |
| `LLMCall` | Makes the LLM API call |
| `ModeRouter` | Routes based on (mode, phase, stop_reason) |
| `TranscriptRecorder` | Logs events to transcript |
| `ToolExecutor` | Executes pending tool calls and re-enters |
| `CommitmentGate` | Detects commitments and ensures follow-through |
| `PlanBuilder` | Generates plan in agentic_planned mode |
| `PlanTracker` | Tracks plan step progress |
| `VerifyPhase` | Runs verification in agentic_planned mode |
| `HumanCheckpoint` | Pauses for human approval in turn_by_turn |
| `WorkspaceSnapshot` | Captures workspace state for planning |

---

## Mode & Phase System

### Modes

- `:agentic` — Full autonomous execution
- `:agentic_planned` — Plan first, then execute, then verify
- `:turn_by_turn` — Propose, human approves, then execute
- `:conversational` — Simple Q&A without tools

### Phases

The phase state machine is defined in `AgentEx.Loop.Phase`:

```
agentic:        init → execute → done
agentic_planned: init → plan → execute → verify → done  
turn_by_turn:   init → review → execute → done
conversational: init → execute → done
```

Phase transitions are validated — invalid transitions return errors.

---

## Storage & Persistence

### Storage Backend

`AgentEx.Storage.Context` provides a unified interface:

```elixir
ctx = AgentEx.Storage.Context.for_workspace("/path/to/workspace", :local)
AgentEx.Storage.Context.read(ctx, "path/to/file")
AgentEx.Storage.Context.write(ctx, "path/to/file", "content")
```

### Persistence Behaviours

| Behaviour | Purpose | Local Implementation |
|-----------|---------|---------------------|
| `AgentEx.Persistence.Transcript` | Session event logging | JSONL files |
| `AgentEx.Persistence.Plan` | Structured plan storage | JSON files |
| `AgentEx.Persistence.Knowledge` | Knowledge graph | JSONL + edges |

---

## Skills System

Skills are folders in `workspace/skills/<name>/` containing:

- `SKILL.md` — YAML frontmatter + markdown body
- `scripts/` — executable scripts
- `references/` — reference files
- `assets/` — static assets

### Skill Service API

```elixir
# List installed skills
AgentEx.Skill.Service.list("/workspace")

# Read skill content
AgentEx.Skill.Service.read("/workspace", "skill-name")

# Search remote skills
AgentEx.Skill.Service.search("query")

# Get skill info without installing
AgentEx.Skill.Service.info("owner/repo")

# Install from GitHub
AgentEx.Skill.Service.install("/workspace", "owner/repo")
AgentEx.Skill.Service.install("/workspace", "owner/repo/path/to/skill")

# Analyze model requirements
AgentEx.Skill.Service.analyze_model_tier("/workspace", "skill-name")
```

---

## Memory System

### ContextKeeper

In-memory Registry-backed context keeper for working memory:

```elixir
AgentEx.Memory.ContextKeeper.start(workspace_id)
AgentEx.Memory.ContextKeeper.put_facts(workspace_id, facts)
AgentEx.Memory.ContextKeeper.get_context(workspace_id)
AgentEx.Memory.ContextKeeper.query(workspace_id, prompt)
```

### MemoryManager

Retrieves relevant context from Knowledge store:

```elixir
AgentEx.Memory.MemoryManager.retrieve_context(
  prompt, 
  workspace, 
  user_id: "...",
  top_k: 10,
  knowledge: %{search: fn -> ... end}
)
```

---

## Subagents

Spawn bounded concurrent subagents for parallel tasks:

```elixir
AgentEx.Subagent.Coordinator.spawn_subagent(
  workspace,
  "Analyze the auth module",
  parent_session_id: "parent-123",
  subagent_depth: 1,
  max_turns: 20,
  callbacks: %{llm_chat: fn -> ... end}
)
```

Default limit: 5 concurrent subagents per workspace.

---

## Example Integration

Here's how to integrate AgentEx into an Elixir application:

```elixir
defmodule MyApp.Agent do
  alias AgentEx
  
  def run_agent(prompt, workspace) do
    callbacks = %{
      llm_chat: &call_openai/1,
      on_event: &handle_event/2,
      execute_tool: &execute_tool/3
    }
    
    AgentEx.run(
      prompt: prompt,
      workspace: workspace,
      callbacks: callbacks,
      profile: :agentic,
      cost_limit: 10.0
    )
  end
  
  defp call_openai(params) do
    # Convert params to OpenAI format, call API, convert back
    response = OpenAI.chat_completion(
      model: "gpt-4o",
      messages: params["messages"],
      tools: params["tools"]
    )
    
    {:ok, %{
      "content" => transform_content(response.choices),
      "stop_reason" => transform_stop_reason(response),
      "usage" => %{
        "input_tokens" => response.usage.prompt_tokens,
        "output_tokens" => response.usage.completion_tokens
      },
      "cost" => calculate_cost(response)
    }}
  end
  
  defp handle_event(event, ctx) do
    # Stream events to UI, log to analytics, etc.
    case event do
      {:turn_start, ...} -> :ok
      {:llm_response, ...} -> :ok
      {:tool_use, ...} -> :ok
      _ -> :ok
    end
  end
  
  defp execute_tool(name, input, ctx) do
    case name do
      "read_file" -> read_file(input["path"], ctx)
      "write_file" -> write_file(input["path"], input["content"], ctx)
      "bash" -> run_bash(input["command"], ctx)
      _ -> {:error, "Unknown tool: #{name}"}
    end
  end
end
```

---

## Configuration

### Application Startup

Add to your `application.ex`:

```elixir
def start(_type, _args) do
  AgentEx.CircuitBreaker.init()
  AgentEx.Application.start(nil, nil)
end
```

### Environment Variables

- `GITHUB_TOKEN` — for GitHub API calls (skills, search)

---

## Telemetry & Observability

AgentEx emits structured telemetry events via the standard `:telemetry` library. Every event uses the `[:agent_ex | ...]` prefix and carries typed measurements and metadata. Attach handlers to observe agent behavior in production.

### Quick Setup

```elixir
# Attach a simple logger to all AgentEx events
:telemetry.attach_many(
  "agent-ex-logger",
  [
    [:agent_ex, :session, :start],
    [:agent_ex, :session, :stop],
    [:agent_ex, :session, :error],
    [:agent_ex, :llm_call, :stop],
    [:agent_ex, :tool, :stop],
    [:agent_ex, :phase, :transition]
  ],
  fn name, measurements, metadata, _config ->
    Logger.info("[telemetry] #{inspect(name)} #{inspect(measurements)} #{inspect(metadata)}")
  end,
  nil
)
```

### Using the Helper Module

`AgentEx.Telemetry` provides two convenience functions:

```elixir
# Emit an event directly
AgentEx.Telemetry.event([:session, :start], %{}, %{session_id: "abc", mode: :agentic})

# Wrap a function in start/stop events
AgentEx.Telemetry.span([:pipeline, :stage, :start], [:pipeline, :stage, :stop], %{}, %{}, fn ->
  do_work()
end)
```

### Event Reference

#### Session Lifecycle

Emitted by `AgentEx.run/1` and `AgentEx.resume/1`.

| Event | When | Measurements | Metadata |
|-------|------|-------------|----------|
| `[:agent_ex, :session, :start]` | Before pipeline begins | — | `session_id`, `mode`, `profile` |
| `[:agent_ex, :session, :stop]` | After pipeline completes | `duration`, `cost`, `tokens`, `steps` | `session_id`, `mode` |
| `[:agent_ex, :session, :error]` | Pipeline crashes | `duration` | `session_id`, `mode`, `error` |
| `[:agent_ex, :session, :resume]` | Session resumed from transcript | — | `session_id`, `turns_restored` |

#### Pipeline Stages

Emitted by `AgentEx.Loop.Engine` for **every** stage in the pipeline.

| Event | When | Measurements | Metadata |
|-------|------|-------------|----------|
| `[:agent_ex, :pipeline, :stage, :start]` | Before stage executes | — | `session_id`, `stage` |
| `[:agent_ex, :pipeline, :stage, :stop]` | After stage completes | `duration` | `session_id`, `stage` |

`stage` is the short module name (e.g. `"LLMCall"`, `"ModeRouter"`).

#### LLM Calls

Emitted by `AgentEx.Loop.Stages.LLMCall`.

| Event | When | Measurements | Metadata |
|-------|------|-------------|----------|
| `[:agent_ex, :llm_call, :start]` | Before calling the LLM | — | `session_id`, `model_tier` |
| `[:agent_ex, :llm_call, :stop]` | After LLM responds | `duration`, `input_tokens`, `output_tokens`, `cost_usd` | `session_id`, `model_tier`, `route` |

`route` is the resolved model ID (e.g. `"gpt-4o"`) or `nil` if routing failed.

#### Tool Execution

Emitted by `AgentEx.Loop.Stages.ToolExecutor`.

| Event | When | Measurements | Metadata |
|-------|------|-------------|----------|
| `[:agent_ex, :tool, :stop]` | After tool completes (success or failure) | `duration`, `output_bytes` | `session_id`, `tool_name`, `success` |

`success` is `true` or `false`.

#### Context Management

Emitted by `AgentEx.Loop.Stages.ContextGuard`.

| Event | When | Measurements | Metadata |
|-------|------|-------------|----------|
| `[:agent_ex, :context, :compact]` | Messages are compacted to save context window | `messages_before`, `messages_after`, `pct_before`, `pct_after` | `session_id` |
| `[:agent_ex, :context, :cost_limit]` | Session hits the cost limit | `cost_usd`, `limit_usd` | `session_id` |

#### Phase Transitions

Emitted by `AgentEx.Loop.Phase.transition/2`.

| Event | When | Measurements | Metadata |
|-------|------|-------------|----------|
| `[:agent_ex, :phase, :transition]` | Phase changes (e.g. `:plan` → `:execute`) | — | `session_id`, `mode`, `from`, `to` |

#### Mode Router

Emitted by `AgentEx.Loop.Stages.ModeRouter` for every routing decision.

| Event | When | Measurements | Metadata |
|-------|------|-------------|----------|
| `[:agent_ex, :mode_router, :route]` | After routing decision | — | `session_id`, `mode`, `phase`, `stop_reason`, `action` |

`action` is one of: `"done"`, `"next"`, `"reentry"`.

#### Commitment Detection

Emitted by `AgentEx.Loop.Stages.CommitmentGate`.

| Event | When | Measurements | Metadata |
|-------|------|-------------|----------|
| `[:agent_ex, :commitment, :detected]` | Agent made a commitment but didn't act | `continuations` | `session_id` |

`continuations` is the total number of commitment continuations so far (max 2 before giving up).

#### Plan Tracking

Emitted by `AgentEx.Loop.Stages.PlanTracker` in `:agentic_planned` mode.

| Event | When | Measurements | Metadata |
|-------|------|-------------|----------|
| `[:agent_ex, :plan, :created]` | Plan is parsed from LLM output | `step_count` | `session_id` |
| `[:agent_ex, :plan, :step, :complete]` | A single plan step is marked complete | — | `session_id`, `step_index`, `total_steps` |
| `[:agent_ex, :plan, :all_complete]` | All plan steps are done | — | `session_id`, `total_steps` |

#### Circuit Breaker

Emitted by `AgentEx.CircuitBreaker` for per-tool failure tracking.

| Event | When | Measurements | Metadata |
|-------|------|-------------|----------|
| `[:agent_ex, :circuit_breaker, :trip]` | Tool failures exceed threshold (circuit opens) | `failure_count` | `tool_name` |
| `[:agent_ex, :circuit_breaker, :recover]` | Tool succeeds after half-open test (circuit closes) | — | `tool_name` |

#### Model Router

Emitted by `AgentEx.ModelRouter.Free` during periodic catalog refreshes.

| Event | When | Measurements | Metadata |
|-------|------|-------------|----------|
| `[:agent_ex, :model_router, :refresh]` | Free model catalog refreshed from OpenRouter | `duration`, `primary_count`, `lightweight_count` | — |

#### Memory System

Emitted by `AgentEx.Memory.ContextKeeper` and `AgentEx.Memory.MemoryManager`.

| Event | When | Measurements | Metadata |
|-------|------|-------------|----------|
| `[:agent_ex, :memory, :ingest]` | Facts are ingested into working memory | `fact_count` | `workspace_id` |
| `[:agent_ex, :memory, :evict]` | Oldest facts are dropped to stay under the 500-entry cap | `evicted_count`, `remaining_count` | `workspace_id` |
| `[:agent_ex, :memory, :retrieval, :stop]` | Context retrieval completes (knowledge store + ContextKeeper) | `duration`, `context_chars`, `cache_hit` | `workspace_id`, `incremental` |

#### Subagent Lifecycle

Emitted by `AgentEx.Subagent.Coordinator`.

| Event | When | Measurements | Metadata |
|-------|------|-------------|----------|
| `[:agent_ex, :subagent, :spawn]` | Subagent task starts | — | `session_id`, `parent_session_id`, `depth` |
| `[:agent_ex, :subagent, :complete]` | Subagent finishes successfully | `duration`, `cost`, `steps` | `session_id`, `parent_session_id` |
| `[:agent_ex, :subagent, :error]` | Subagent fails | `duration` | `session_id`, `parent_session_id`, `error` |

### Typical Dashboard Metrics

Wire these events into your observability stack (Telegraf, StatsD, Prometheus via `telemetry_metrics`, etc.):

| Metric | Event | Aggregation |
|--------|-------|------------|
| Session duration p50/p99 | `[:session, :stop]` → `duration` | distribution |
| Session cost | `[:session, :stop]` → `cost` | sum |
| LLM latency p50/p99 | `[:llm_call, :stop]` → `duration` | distribution |
| Token usage | `[:llm_call, :stop]` → `input_tokens` + `output_tokens` | sum |
| Tool latency by name | `[:tool, :stop]` → `duration` (group by `tool_name`) | distribution |
| Tool error rate | `[:tool, :stop]` where `success == false` | count |
| Context compactions | `[:context, :compact]` | count |
| Cost limit hits | `[:context, :cost_limit]` | count |
| Circuit breaker trips | `[:circuit_breaker, :trip]` | count |
| Commitment gate triggers | `[:commitment, :detected]` | count |
| Subagent spawn rate | `[:subagent, :spawn]` | count |
| Plan step throughput | `[:plan, :step, :complete]` | count |

### Attaching with Telemetry.Metrics

```elixir
# In your application supervisor children:
{Telemetry.Metrics.ConsoleReporter, metrics: AgentEx.Telemetry.metrics()}

# Or define metrics manually:
Telemetry.Metrics.summary([:agent_ex, :llm_call, :stop], :duration, unit: {:native, :millisecond})
Telemetry.Metrics.counter([:agent_ex, :tool, :stop], tags: [:tool_name, :success])
Telemetry.Metrics.distribution([:agent_ex, :session, :stop], :duration)
```

---

## Testing

Use the test helpers:

```elixir
defmodule MyAppTest do
  use ExUnit.Case, async: true
  
  test "runs agent" do
    callbacks = AgentEx.TestHelpers.mock_callbacks(%{
      llm_chat: fn _ ->
        {:ok, %{
          "content" => [%{"type" => "text", "text" => "Done!"}],
          "stop_reason" => "end_turn"
        }}
      end
    })
    
    ctx = AgentEx.TestHelpers.build_ctx(callbacks: callbacks)
    
    # Run test
  end
end
```

---

## Architecture Summary

```
┌─────────────────────────────────────────────────────────────────┐
│                         Host Application                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   AgentEx.run()                                                 │
│        │                                                         │
│   ┌────▼────────────────────────────────────────────────────┐   │
│   │                    Engine.run(ctx, stages)              │   │
│   │                                                        │   │
│   │   Context.new()                                         │   │
│   │        │                                                │   │
│   │   Profile.stages(profile)                              │   │
│   │        │                                                │   │
│   │   [ContextGuard → ProgressInjector → LLMCall →        │   │
│   │        ModeRouter → TranscriptRecorder →              │   │
│   │        ToolExecutor → CommitmentGate]                  │   │
│   │                                                        │   │
│   │   Each stage: call(ctx, next) -> ctx | {:done, res}  │   │
│   └────────────────────────────────────────────────────────┘   │
│                                                                  │
│        │                    │                    │               │
│   ┌────▼────┐         ┌────▼────┐         ┌────▼────┐         │
│   │  Tools  │         │ Skills  │         │Memory/  │         │
│   │         │         │Service  │         │Knowledge│         │
│   └─────────┘         └─────────┘         └─────────┘         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Further Reference

- **AGENTS.md** — Workspace operating guidelines
- **priv/core_skills/** — Built-in skill definitions
- **priv/prompts/** — Prompt templates
- **Test files** in `test/agent_ex/` for usage patterns