# Agentic Multi-Mode Loop — Implementation Proposal

> **Companion documents:**
>
> - [Persistence Strategy](./persistence-strategy.md) — behaviour definitions, Recollect integration, host app guide
> - [Decisions](./decisions.md) — design decisions log with rationale

## 1. Goals

Add multiple execution modes to the agent loop so a single `Agentic.run/1` call can behave very differently depending on the chosen mode:

| Mode | Behavior |
|---|---|
| `:agentic` | Current behavior. Autonomous tool-use loop, no human input mid-run. |
| `:agentic_planned` | Two-phase: LLM produces a step-by-step plan first, then executes each step autonomously with plan tracking and verification. |
| `:turn_by_turn` | LLM breaks the problem into small chunks, proposes each chunk to a human for approval/revision before acting. Agent never proceeds without acknowledgment. |
| `:conversational` | Current behavior. Single call-respond, no tools. |

All modes must coexist with the existing middleware pipeline architecture. Existing tests must continue to pass with no changes.

---

## 2. Design Principles

1. **Modes compose from the same stage primitives.** No fork of the pipeline engine or stage behaviour.
2. **A single new stage owns mode-specific routing.** Called `ModeRouter`. It replaces `StopReasonRouter` entirely.
3. **Phase transitions are validated by `Agentic.Loop.Phase`.** A lightweight state machine module with per-mode transition maps. `Phase.transition(ctx, next_phase)` returns `{:ok, ctx}` or `{:error, {:invalid_transition, from, to}}`. Stages call this instead of mutating `ctx.phase` directly.
4. **Human-in-the-loop is a callback, not a process.** A new `:on_human_input` callback on `ctx.callbacks` lets the host application decide how to present and collect human responses (CLI prompt, WebSocket, message queue, etc.).
5. **`ModeRouter` replaces `StopReasonRouter` in all profiles.** No backward compatibility layer — `StopReasonRouter` is removed. The `:agentic` mode's routing logic lives inside `ModeRouter` as a clause.

---

## 3. Context Changes

### 3.1 New fields on `Agentic.Loop.Context`

The current `defstruct` (see `lib/agentic/loop/context.ex`) already has `phase: :execute`. New fields are added with defaults that match current behavior:

| Field | Type | Default | Purpose |
|---|---|---|---|
| `mode` | `:agentic \| :agentic_planned \| :turn_by_turn \| :conversational` | `:agentic` | Active execution mode |
| `phase` | `:plan \| :execute \| :verify \| :review \| :done` | `:execute` | *(exists today, extended range)* |
| `plan` | `map() \| nil` | `nil` | Structured plan from `:agentic_planned` phase |
| `plan_step_index` | `integer()` | `0` | Which plan step is currently executing |
| `plan_steps_completed` | `list(integer())` | `[]` | Indices of completed steps |
| `human_input` | `String.t() \| nil` | `nil` | Last human response from `:turn_by_turn` checkpoint |
| `pending_human_response` | `boolean()` | `false` | Whether the loop is waiting for human input |
| `workspace_snapshot` | `String.t() \| nil` | `nil` | Populated on first pass by `WorkspaceSnapshot` stage |
| `file_reads` | `%{path => %{hash: String.t(), last_read_turn: integer()}}` | `%{}` | Deduplication tracking for file reads |

### 3.2 `Agentic.Loop.Phase` — phase state machine

A lightweight module (~60 lines) with validated transition maps. No external dependency — plain data + pattern matching is the right fit for a pure-function pipeline (confirmed by `fsm` library author's own advice: "regular data structures with pattern matching in multiclauses will serve you just fine"). Process-based FSMs like `gen_statem` are architecturally wrong here — our state threads through stage functions, not a long-lived GenServer.

**File:** `lib/agentic/loop/phase.ex`

```elixir
defmodule Agentic.Loop.Phase do
  @moduledoc "Phase state machine with per-mode validated transitions."

  @phases [:init, :plan, :execute, :review, :verify, :done]

  @mode_transitions %{
    agentic: %{
      init:     [:execute],
      execute:  [:execute, :done],
      done:     []
    },
    agentic_planned: %{
      init:     [:plan],
      plan:     [:execute],
      execute:  [:execute, :verify],
      verify:   [:done],
      done:     []
    },
    turn_by_turn: %{
      init:     [:review],
      review:   [:review, :execute],
      execute:  [:review, :done],
      done:     []
    },
    conversational: %{
      init:     [:execute],
      execute:  [:done],
      done:     []
    }
  }

  def phases, do: @phases
  def mode_transitions, do: @mode_transitions

  def transition(ctx, next_phase) do
    transitions = Map.get(@mode_transitions, ctx.mode, %{})
    allowed = Map.get(transitions, ctx.phase, [])

    if next_phase in allowed do
      {:ok, %{ctx | phase: next_phase}}
    else
      {:error, {:invalid_transition, ctx.mode, ctx.phase, next_phase}}
    end
  end

  def transition!(ctx, next_phase) do
    case transition(ctx, next_phase) do
      {:ok, ctx} -> ctx
      {:error, reason} -> raise "Invalid phase transition: #{inspect(reason)}"
    end
  end

  def valid?(ctx, next_phase) do
    transitions = Map.get(@mode_transitions, ctx.mode, %{})
    next_phase in Map.get(transitions, ctx.phase, [])
  end

  def initial_phase(:agentic), do: :execute
  def initial_phase(:agentic_planned), do: :plan
  def initial_phase(:turn_by_turn), do: :review
  def initial_phase(:conversational), do: :execute
end
```

**Transition diagrams per mode:**

**`:agentic`:**
```
init → :execute → (loop via tool_use) → :execute → ... → :done
```

**`:agentic_planned`:**
```
init → :plan → (LLM produces plan) → :execute → (loop per step) → :execute → ... → :verify → (LLM verifies) → :done
```

**`:turn_by_turn`:**
```
init → :review → (LLM proposes, human approves) → :execute → (tools run) → :review → ... → :done
```

**`:conversational`:**
```
init → :execute → :done
```

All phase transitions in stages go through `Phase.transition(ctx, next_phase)` — never direct `ctx.phase` mutation. This gives compile-time safety via `transition!` in hot paths and `{:error, _}` returns for graceful handling elsewhere.

---

## 4. New Callbacks

All new callbacks follow the existing callback pattern. They are optional — `nil` values are handled gracefully.

### 4.1 `:on_human_input`

```elixir
# Type: (proposal :: map(), ctx :: Context.t()) ->
#   {:approve, ctx} | {:approve, feedback :: String.t(), ctx} | {:abort, reason :: String.t()}
```

Called by the `HumanCheckpoint` stage when the agent has a proposal for the human. The callback receives a `proposal` map:

```elixir
%{
  thinking: "I'll refactor the module into 3 smaller files",
  steps: ["Extract Foo", "Extract Bar", "Update imports"],
  risks: ["May break existing tests"],
  tool_preview: ["read_file", "write_file", "bash"]
}
```

The callback returns:
- `{:approve, ctx}` — proceed as proposed
- `{:approve, feedback, ctx}` — proceed but incorporate feedback
- `{:abort, reason}` — stop the loop, return partial results

### 4.2 `:on_plan_created`

```elixir
# Type: (plan :: map(), ctx :: Context.t()) -> {:ok, ctx} | {:revise, feedback :: String.t(), ctx}
```

Optional. Called after the LLM produces a plan in `:agentic_planned` mode. Allows the host to log, display, or reject the plan before execution starts. Return `{:revise, feedback, ctx}` to send the LLM back to planning with feedback.

### 4.3 `:on_step_complete`

```elixir
# Type: (step :: map(), result :: map(), ctx :: Context.t()) -> :ok
```

Optional. Called after each plan step completes in `:agentic_planned` mode. For progress tracking and logging.

### 4.4 `:on_tool_approval`

```elixir
# Type: (tool_name :: String.t(), input :: map(), ctx :: Context.t()) ->
#   :approved | :denied | {:approved_with_changes, new_input :: map()}
```

Optional. Called before tool execution when `ctx.tool_permissions[tool_name] == :approve`. See [Persistence Strategy §16](./persistence-strategy.md#e5-tool-permission-and-approval-gating) for the full permission gating spec.

### 4.5 `:on_workspace_snapshot`

```elixir
# Type: (workspace_path :: String.t()) -> {:ok, snapshot_string :: String.t()} | {:error, term()}
```

Optional. If provided, the host supplies its own workspace snapshot. If not, `WorkspaceSnapshot` gathers it automatically.

---

## 5. New Stages

All stages implement `@behaviour Agentic.Loop.Stage` (requiring `call/2` that receives `ctx` and `next`). `StopReasonRouter` is removed; `ModeRouter` handles all routing.

### 5.1 `ModeRouter`

**File:** `lib/agentic/loop/stages/mode_router.ex`

Reads `ctx.mode` and `ctx.phase` to decide what to do with the LLM response. All phase transitions go through `Phase.transition/2`.

Responsibilities:
- Extract text and tool calls from LLM response
- Route to the correct next stage based on `(mode, phase, stop_reason)` triple
- Enforce valid phase transitions via `Phase.transition/2`
- Enforce `max_turns` safety rail

Routing table:

| Mode | Phase | Stop Reason | Action |
|---|---|---|---|
| `:agentic` | `:execute` | `end_turn` | Accumulate text → next (CommitmentGate) |
| `:agentic` | `:execute` | `tool_use` | Store pending_tool_calls → next (ToolExecutor) |
| `:agentic_planned` | `:plan` | `end_turn` | Parse plan from response → store on ctx → transition to `:execute` → reentry |
| `:agentic_planned` | `:execute` | `end_turn` | Mark step complete → check if more steps → reentry or transition to `:verify` |
| `:agentic_planned` | `:execute` | `tool_use` | Store pending_tool_calls → next (ToolExecutor) |
| `:agentic_planned` | `:verify` | `end_turn` | Accumulate verification result → done |
| `:turn_by_turn` | `:review` | `end_turn` | Build proposal → next (HumanCheckpoint) |
| `:turn_by_turn` | `:review` | `tool_use` | Store pending_tool_calls → next (ToolExecutor) |
| `:turn_by_turn` | `:execute` | `end_turn` | Transition to `:review` → reentry |
| `:turn_by_turn` | `:execute` | `tool_use` | Store pending_tool_calls → next (ToolExecutor) |
| `:conversational` | `:execute` | `end_turn` | Accumulate text → done |
| any | any | `max_tokens` | Return what we have → done |

When no specific match, fall through to `end_turn → done`.

### 5.2 `PlanBuilder`

**File:** `lib/agentic/loop/stages/plan_builder.ex`

Only active in `:agentic_planned` mode when `ctx.phase == :plan`. Injected before `LLMCall` by the profile.

Responsibilities:
- On first call: inject a structured plan-request prompt into messages asking the LLM to decompose the task
- On subsequent calls (after revision): the revision feedback is already in messages, pass through
- Does not call `next` itself — it modifies messages and lets `LLMCall` follow in the pipeline

This is a thin prompt-engineering stage. It appends a user message like:

> "Break this task into a numbered list of concrete steps. For each step, describe: what to do, which tools you'll use, and how to verify it worked. Output the plan as JSON matching this schema: {\"steps\": [{\"index\": int, \"description\": str, \"tools\": [str], \"verification\": str}]}. Output ONLY the plan, no execution."

**Plan parsing uses JSON.** The prompt requests structured JSON output. If the LLM fails to produce valid JSON, `PlanBuilder` falls back to free-text heuristic parsing. This works best with providers that support JSON mode, but degrades gracefully.

After `LLMCall` runs and `ModeRouter` sees `:plan` + `end_turn`, it parses the response into a plan struct and transitions to `:execute`.

### 5.3 `PlanTracker`

**File:** `lib/agentic/loop/stages/plan_tracker.ex`

Only active in `:agentic_planned` mode when `ctx.phase == :execute`. Sits after `ToolExecutor`.

Responsibilities:
- After each LLM response, determine which plan step was just worked on (match tool usage to step descriptions, or ask LLM to self-tag)
- Increment `ctx.plan_step_index` when a step appears complete
- Inject a progress message into the conversation: "Step 3/7 complete. Next step: ..."
- When all steps are complete, set `ctx.phase = :verify`
- Call `:on_step_complete` callback if provided

**Plan completion detection** uses the `ContinuationDetector` module. Primary strategy: LLM self-reports step completion in its response (prompt engineering). Fallback: after N turns per step, prompt the LLM to confirm completion.

### 5.4 `HumanCheckpoint`

**File:** `lib/agentic/loop/stages/human_checkpoint.ex`

Only active in `:turn_by_turn` mode. Sits after `ModeRouter`.

Responsibilities:
- When `ctx.phase == :review` and agent produced text (not tool calls): build a `proposal` map from the response, call `ctx.callbacks[:on_human_input].(proposal, ctx)`
- On `{:approve, ctx}` — set `ctx.phase = :execute`, append human approval to messages, reentry
- On `{:approve, feedback, ctx}` — append feedback to messages, set `ctx.phase = :execute`, reentry
- On `{:abort, reason}` — return `{:done, result}` with partial text and abort reason
- When `ctx.phase == :execute` — pass through (tools should execute normally)

**Chunk granularity:** The LLM decides per-turn how much to propose. The human provides the feedback loop that naturally constrains scope.

**Timeout handling:** The `on_human_input` callback is synchronous from the loop's perspective. Timeout behavior is the host's responsibility — the loop does not impose one.

### 5.5 `VerifyPhase`

**File:** `lib/agentic/loop/stages/verify_phase.ex`

Only active in `:agentic_planned` mode when `ctx.phase == :verify`. Injected before `LLMCall`.

Responsibilities:
- Inject a verification prompt: "Here was the original plan: ... Here is what was done: ... Verify each step was completed correctly. Report any issues."
- Let `LLMCall` run, then `ModeRouter` handles the `:verify` + `end_turn` case → done

### 5.6 `WorkspaceSnapshot`

**File:** `lib/agentic/loop/stages/workspace_snapshot.ex`

Only active on the first pipeline pass (`ctx.turns_used == 0`). Sits before `ContextGuard` in every pipeline.

Responsibilities:
- Gather workspace context: git branch/status/recent commits, file tree, instruction files, project config
- Inject a structured workspace context message into `ctx.messages` as the first user message (after system prompt)
- Check `ctx.callbacks[:on_workspace_snapshot]` — if provided, use the host's snapshot; otherwise gather automatically
- On subsequent passes, no-ops (the snapshot is already in messages)

Uses budget-aware assembly patterns for the workspace snapshot.
---

## 6. Profile Changes

`Agentic.Loop.Profile` (see `lib/agentic/loop/profile.ex`) gains new profile definitions. The current `stages/1` function pattern-matches on atoms and returns stage lists. New clauses are added:

### `:agentic`
```
ContextGuard → ProgressInjector → LLMCall → ModeRouter → ToolExecutor → CommitmentGate
```

### `:agentic_planned` (new)
```
WorkspaceSnapshot → ContextGuard → PlanBuilder → ProgressInjector → LLMCall → ModeRouter → ToolExecutor → PlanTracker → CommitmentGate
```

Config:
```elixir
%{
  max_turns: 100,
  compaction_at_pct: 0.80,
  progress_injection: :system_reminder,
  require_plan_verification: true,
  max_plan_steps: 20,
  telemetry_prefix: [:agentic]
}
```

### `:turn_by_turn` (new)
```
WorkspaceSnapshot → ContextGuard → LLMCall → ModeRouter → HumanCheckpoint → ToolExecutor → CommitmentGate
```

Config:
```elixir
%{
  max_turns: 200,
  compaction_at_pct: 0.80,
  progress_injection: :none,
  max_chunks_per_session: 50,
  telemetry_prefix: [:agentic]
}
```

No `ProgressInjector` — the human is the progress mechanism. `CommitmentGate` stays as a safety net.

### `:conversational`
```
ContextGuard → LLMCall → ModeRouter
```

### Profile selection

`Agentic.run/1` gains an optional `:mode` keyword. The mapping:

```elixir
mode                →  profile              →  stages
:agentic            → :agentic              → (current)
:agentic_planned    → :agentic_planned      → (new)
:turn_by_turn       → :turn_by_turn         → (new)
:conversational     → :conversational       → (current)
```

If `:mode` is not provided, the existing `:profile` key is used directly. If `:mode` is provided, it overrides `:profile`. Default mode is `:agentic`.

---

## 7. `Agentic.run/1` API Changes

Current (see `lib/agentic.ex`):
```elixir
Agentic.run(
  prompt: "...",
  workspace: "/path",
  callbacks: %{llm_chat: fn params -> ... end}
)
```

New optional keys:
```elixir
Agentic.run(
  prompt: "...",
  workspace: "/path",
  callbacks: %{llm_chat: ..., on_human_input: ...},
  mode: :agentic_planned,
  plan: %{steps: [...]}
)
```

If `plan` is provided with `mode: :agentic_planned`, the `:plan` phase is skipped entirely — execution starts immediately against the provided plan. This lets the host application produce plans externally.

Implementation: add `:mode` to the keyword list processing in `run/1`, resolve it to a profile name, and pass it to `Profile.stages/1` and `Profile.config/1`.

---

## 8. Plan Structure

The plan stored on `ctx.plan`:

```elixir
%{
  id: "pln-abc123",
  goal: "Refactor the auth module into separate concerns",
  steps: [
    %{
      index: 0,
      description: "Read current auth.ex and map all public functions",
      tools: ["read_file", "list_files"],
      verification: "Confirm we have a complete list of public functions",
      status: :pending
    },
    %{
      index: 1,
      description: "Extract authentication logic into auth/authentication.ex",
      tools: ["write_file", "edit_file"],
      verification: "Module compiles, all auth functions are present",
      status: :pending
    }
  ]
}
```

Step status values: `:pending | :in_progress | :complete | :failed`

Parsing the plan from LLM output is a prompt-engineering problem. The `PlanBuilder` stage will include structured output instructions. If parsing fails (LLM doesn't produce valid plan structure), `ModeRouter` falls back to treating it as a regular `:agentic` turn.

---

## 9. Turn-by-Turn Proposal Structure

The proposal passed to `on_human_input`:

```elixir
%{
  chunk_number: 3,
  total_chunks: nil,
  thinking: "The tests are failing because the module uses old config keys",
  proposed_action: "Update config keys in test_helper.exs and re-run tests",
  tools_needed: ["edit_file", "bash"],
  risks: ["Tests may still fail if other files reference old keys"],
  confidence: 0.8,
  can_proceed_independently: true
}
```

The agent is prompted to produce this structure. Like plan parsing, this is prompt engineering. A simpler fallback: the proposal is just the raw LLM text, and the host renders it as-is.

---

## 10. Implementation Order

This library has no existing consumers, so all changes are applied directly — no migration path needed.

1. **`Phase` module** — transition maps and `transition/2`, `initial_phase/1`
2. **Context fields** — add `mode`, `plan`, `plan_step_index`, `plan_steps_completed`, `human_input`, `pending_human_response`, `workspace_snapshot`, `file_reads`
3. **`ModeRouter`** — replaces `StopReasonRouter` entirely. Delete `StopReasonRouter`.
4. **New stages** — `PlanBuilder`, `PlanTracker`, `HumanCheckpoint`, `VerifyPhase`, `WorkspaceSnapshot`
5. **New profiles** — `:agentic_planned`, `:turn_by_turn`. Update `:agentic` and `:conversational` to use `ModeRouter`.
6. **Entry point** — add `:mode` opt to `Agentic.run/1`, wire new callbacks

---

## 11. Design Decisions

| Topic | Decision | Where |
|---|---|---|
| Plan parsing | Prefer JSON output from LLM. Fallback to free-text heuristic parsing. | §5.2 PlanBuilder |
| Step completion detection | LLM self-reports completion (prompt engineering). After N turns per step, prompt LLM to confirm (fallback). | §5.3 PlanTracker |
| Chunk granularity | LLM decides per-turn how much to propose. Human feedback loop constrains scope naturally. | §5.4 HumanCheckpoint |
| Human timeout | Host's responsibility. `on_human_input` is synchronous from the loop's perspective. | §5.4 HumanCheckpoint |
| Mode switching mid-run | Not possible in V1. Mode is set at `run/1` time and fixed for the session. | §7 API Changes |
