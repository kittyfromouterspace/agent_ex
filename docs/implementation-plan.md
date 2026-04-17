# Implementation Plan — Agentic Multi-Mode Loop

> Companion to [Main Proposal](./multi-mode-loop-proposal.md). Covers phased implementation order, testing strategy, and complete file manifest.

---

## 1. Phased Implementation Order

Combining the multi-mode proposal (Main Proposal §1–11), gap analysis enhancements (E1–E6), persistence strategy, and porting priorities.

| Phase | Scope | Details |
|---|---|---|
| **V1.0** | Multi-mode core + persistence behaviours | `Phase` state machine module, new Context fields, `ModeRouter` (replaces `StopReasonRouter`), `PlanBuilder`, `PlanTracker`, `HumanCheckpoint`, `VerifyPhase`, new profiles (all using `ModeRouter`), persistence behaviour definitions with `:local` backends, `ContinuationDetector` port, callback architecture. |
| **V1.1** | Workspace snapshot + output clipping + deduplication + Recollect knowledge backend | WorkspaceSnapshot stage, per-tool output clipping in ToolExecutor, file-read deduplication in ContextGuard, `:recollect` Knowledge backend, ported ContextAssembler utilities, ported MemoryManager.optimize_context pattern. |
| **V1.2** | Prompt prefix / cache awareness | LLMCall restructured with stable/volatile separation, cache boundary markers, `stable_prefix_hash` context field. |
| **V1.3** | Full transcript + session resumption | TranscriptRecorder stage, `Agentic.resume/1`, JSONL persistence, plan state serialization in transcript. |
| **V2.0** | Bounded subagents + ported patterns | Ported Coordinator architecture, `delegate_task` tool, LLMSemaphore, subagent depth/budget fields. |
| **V2.1** | Tool permission gating | `tool_permissions` context field, `:on_tool_approval` callback, ToolExecutor pre-check. |

V1.1 is the highest-value enhancement because it directly improves `:agentic_planned` robustness. Subagents (V2.0) are the highest-impact architectural addition but also the most complex.

---

## 2. Testing Strategy

Testing follows the existing patterns in `test/support/test_helpers.ex` (`mock_callbacks/1`, `build_ctx/1`, `create_test_workspace/0`). The existing `Agentic.Loop.Stage` behaviour means every stage is testable in isolation by calling `Stage.call(ctx, next_fn)` with a mock `next`.

### 2.1 Unit Tests (per-stage)

Each new stage gets its own test file in `test/agentic/loop/stages/`:

| Test File | What It Tests |
|---|---|
| `mode_router_test.exs` | Routing table correctness for all `(mode, phase, stop_reason)` combinations. Phase transition side effects via `Phase.transition/2`. Phase transition on ctx. |
| `plan_builder_test.exs` | Plan-request prompt injection on first call. Pass-through on revision (feedback already in messages). No-op when `phase != :plan`. |
| `plan_tracker_test.exs` | Step completion detection via regex patterns (ported from ContinuationDetector). `plan_step_index` increment. Phase transition to `:verify` when all steps complete. `:on_step_complete` callback invocation. |
| `human_checkpoint_test.exs` | `{:approve, ctx}` sets phase to `:execute`. `{:approve, feedback, ctx}` appends feedback. `{:abort, reason}` returns partial result. Pass-through when `phase == :execute`. Proposal map construction from LLM response. |
| `verify_phase_test.exs` | Verification prompt injection. No-op when `phase != :verify`. |
| `workspace_snapshot_test.exs` | Snapshot gathered on `turns_used == 0`. No-op on subsequent passes. Host callback override via `:on_workspace_snapshot`. Git/file-tree/config gathering. |

Mock pattern: override `llm_chat` in `mock_callbacks/1` to return specific `stop_reason` and `content` structures. Example:

```elixir
test "mode_router routes agentic_planned plan end_turn to execute phase" do
  ctx = build_ctx(
    mode: :agentic_planned,
    phase: :plan,
    last_response: %{
      "stop_reason" => "end_turn",
      "content" => [%{"type" => "text", "text" => "Step 1: Read files\nStep 2: Edit"}]
    }
  )
  # ... assert phase transition
end
```

### 2.2 Integration Tests (per-mode)

End-to-end tests for each mode using `build_ctx/1` with full pipeline:

| Test File | What It Tests |
|---|---|
| `agentic_planned_test.exs` | Full plan → execute → verify lifecycle. Plan parsing from LLM output. Step completion across multiple tool-use turns. Verify phase produces final summary. Pre-built plan skips `:plan` phase. |
| `turn_by_turn_test.exs` | Human approval flow (proceed with tools). Human revision flow (agent re-thinks). Abort flow (partial results). Multiple chunks with review→execute→review cycling. |

Regression: existing `agentic_test.exs` and `integration_test.exs` must pass unchanged.

### 2.3 Persistence Backend Tests

Each behaviour gets contract tests verifying the `:local` implementation:

| Test File | What It Tests |
|---|---|
| `persistence/transcript_local_test.exs` | JSONL `append`, `load`, `load_since`, `list_sessions`. Append-only correctness. Session not found. Event ordering. |
| `persistence/plan_local_test.exs` | JSON `create`, `get`, `update_step`, `list_plans`. Step status transitions (`:pending → :in_progress → :complete`). Plan not found. |
| `persistence/knowledge_local_test.exs` | Entry `create_entry`, `search` (keyword-based for `:local`), `recent`, `create_edge`, `get_edges`. Supersede demotes confidence. |
| `persistence/knowledge_recollect_test.exs` | Recollect backend. Tagged `@tag :recollect` — only runs when Recollect DB is configured. Tests `search`, `create_entry`, `connect`, `supersede`. |

Contract test pattern: define shared test macros per behaviour, run against each backend module. This ensures `:local` and `:recollect` produce compatible results.

### 2.4 Porting Tests

For code ported from neighboring codebases:

| Test File | Source | What It Tests |
|---|---|---|
| `continuation_detector_test.exs` | Homunculus | All 5 detection categories. False positive filtering. `:steps` option suppression. Edge cases (nil, empty string). |
| `context_compression_test.exs` | Homunculus | Two-tier: truncation <2× budget, LLM summarization ≥2× budget. Fallback to truncation on LLM error. Pass-through when under budget. |
| `llm_semaphore_test.exs` | SCE | Concurrency limit enforcement. Automatic permit release on process crash. FIFO ordering. Stats reporting. |

### 2.5 Regression Guards

- All existing test files must pass (they will be updated to use `ModeRouter` instead of `StopReasonRouter`)
- New Context fields have sensible defaults (`mode: :agentic`, `phase: :execute`, etc.)
- All profiles use `ModeRouter` — `StopReasonRouter` is deleted
- `mix test` continues to work with ecto no-ops (Repo will be added by Recollect config, not by Agentic)

### 2.6 Test Helper Additions

New helpers in `test/support/test_helpers.ex`:

```elixir
def mock_human_callback(responses) do
  {:erlang.make_ref(), responses}
  |> then(fn {ref, responses} ->
    fn proposal, ctx ->
      send(ctx.caller, {:human_checkpoint, proposal})
      case responses do
        [{tag, resp} | rest] ->
          send(ctx.caller, {ref, {tag, resp}})
          {{tag, resp}, ctx}
        [] ->
          {:abort, "no more responses"}
      end
    end
  end)
end

def build_planned_ctx(overrides \\ []) do
  build_ctx(Keyword.merge([mode: :agentic_planned, phase: :plan], overrides))
end

def build_turn_by_turn_ctx(overrides \\ []) do
  build_ctx(Keyword.merge([
    mode: :turn_by_turn,
    phase: :review,
    callbacks: mock_callbacks(on_human_input: mock_human_callback([{:approve, "ok"}]))
  ], overrides))
end

def mock_llm_plan_response(steps) do
  fn _params ->
    text = Enum.map_join(steps, "\n", fn s -> "Step #{s.index + 1}: #{s.description}" end)
    {:ok, %{
      "content" => [%{"type" => "text", "text" => text}],
      "stop_reason" => "end_turn",
      "usage" => %{"input_tokens" => 100, "output_tokens" => 80},
      "cost" => 0.002
    }}
  end
end
```

---

## 3. File Manifest

### New Files

**Stages** (lib/agentic/loop/stages/):

| File | Section | Description |
|---|---|---|
| `mode_router.ex` | Main §5.1 | Mode-aware routing stage (replaces `StopReasonRouter`) |
| `plan_builder.ex` | Main §5.2 | Plan prompt injection stage |
| `plan_tracker.ex` | Main §5.3 | Plan step tracking stage |
| `human_checkpoint.ex` | Main §5.4 | Human-in-the-loop yield stage |
| `verify_phase.ex` | Main §5.5 | Post-execution verification stage |
| `workspace_snapshot.ex` | Main §5.6 | Workspace context gathering stage |
| `transcript_recorder.ex` | Gap E4 | Session event recording stage |

**State machine** (lib/agentic/loop/):

| File | Section | Description |
|---|---|---|
| `phase.ex` | Main §3.2 | Phase state machine with per-mode transition maps |

**Persistence behaviours** (lib/agentic/persistence/):

| File | Description |
|---|---|
| `transcript.ex` | Transcript behaviour definition |
| `transcript/local.ex` | JSONL file transcript backend |
| `plan.ex` | Plan persistence behaviour definition |
| `plan/local.ex` | JSON file plan backend |
| `knowledge.ex` | Knowledge behaviour definition |
| `knowledge/local.ex` | File-based knowledge backend |
| `knowledge/recollect.ex` | Recollect-backed knowledge backend |

**Ported utilities** (lib/agentic/):

| File | Source | Description |
|---|---|---|
| `loop/continuation_detector.ex` | Homunculus | Plan/completion detection via regex |
| `loop/context_compression.ex` | Homunculus | Two-tier truncate/summarize |
| `concurrency/semaphore.ex` | SCE | Bounded concurrency GenServer |

**Test files** (test/):

| File | Description |
|---|---|
| `agentic/loop/stages/mode_router_test.exs` | ModeRouter unit tests |
| `agentic/loop/phase_test.exs` | Phase state machine tests (transition validation per mode, invalid transitions, initial_phase/1) |
| `agentic/loop/stages/plan_builder_test.exs` | PlanBuilder unit tests |
| `agentic/loop/stages/plan_tracker_test.exs` | PlanTracker unit tests |
| `agentic/loop/stages/human_checkpoint_test.exs` | HumanCheckpoint unit tests |
| `agentic/loop/stages/verify_phase_test.exs` | VerifyPhase unit tests |
| `agentic/loop/stages/workspace_snapshot_test.exs` | WorkspaceSnapshot unit tests |
| `agentic/loop/agentic_planned_test.exs` | Planned mode integration test |
| `agentic/loop/turn_by_turn_test.exs` | Turn-by-turn mode integration test |
| `agentic/persistence/transcript_local_test.exs` | Transcript backend tests |
| `agentic/persistence/plan_local_test.exs` | Plan backend tests |
| `agentic/persistence/knowledge_local_test.exs` | Knowledge local backend tests |
| `agentic/persistence/knowledge_recollect_test.exs` | Knowledge Recollect backend tests |
| `agentic/loop/continuation_detector_test.exs` | Ported from Homunculus |
| `agentic/loop/context_compression_test.exs` | Ported from Homunculus |
| `agentic/concurrency/semaphore_test.exs` | Ported from SCE |

### Modified Files

| File | Change |
|---|---|
| `lib/agentic/loop/context.ex` | Add new fields (`mode`, `plan`, `plan_step_index`, `plan_steps_completed`, `human_input`, `pending_human_response`, `workspace_snapshot`, `file_reads`). |
| `lib/agentic/loop/profile.ex` | Add `stages(:agentic_planned)`, `stages(:turn_by_turn)`, `config(:agentic_planned)`, `config(:turn_by_turn)` clauses. Update `:agentic` and `:conversational` to use `ModeRouter`. |
| `lib/agentic.ex` | Add `:mode` opt to `run/1`. Resolve mode to profile. Add `resume/1` function. Wire new callbacks. |
| `lib/agentic/storage/context.ex` | Add `@behaviour` reference for compile-time enforcement. |
| `lib/agentic/storage/local.ex` | Add `@behaviour` implementation. |
| `lib/agentic/loop/stages/context_guard.ex` | Add file-read deduplication logic using `ctx.file_reads`. Add per-tool output clipping config. |
| `lib/agentic/loop/stages/tool_executor.ex` | Respect `tool_permissions` before execution. Apply per-tool `max_output_bytes` clipping. |
| `lib/agentic/loop/stages/llm_call.ex` | Add cache boundary markers (stable/volatile separation). |
| `test/support/test_helpers.ex` | Add `mock_human_callback/1`, `build_planned_ctx/1`, `build_turn_by_turn_ctx/1`, `mock_llm_plan_response/1`. |
| `mix.exs` | Remove `ecto.setup`/`ecto.reset` aliases (no longer no-ops once Recollect is configured). Keep `ecto_sql`/`postgrex` deps (required by recollect). |

### Deleted Files

| File | Reason |
|---|---|
| `lib/agentic/loop/stages/stop_reason_router.ex` | Replaced by `mode_router.ex` |
| `test/agentic/loop/stages/stop_reason_router_test.exs` | Replaced by `mode_router_test.exs` |

### Unchanged Files

Existing stage files `commitment_gate.ex` and `progress_injector.ex` remain unchanged. Other existing test files remain unchanged.
