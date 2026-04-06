# V1.0 Implementation Progress

> Tracks the V1.0 multi-mode loop refactor. See [decisions.md](./decisions.md) for design decisions log.



## Status: COMPLETE

 All items below are done.



- [ ] Not started
- [~] In progress
- [x] Complete
- [-] Skipped / deferred

---

## Phase 1: Core Infrastructure

### Step 1: Phase State Machine (`lib/agent_ex/loop/phase.ex`)
- [x] Create `AgentEx.Loop.Phase` module
- [x] Define `@mode_transitions` map for all 4 modes
- [x] Implement `transition/2`, `transition!/2`, `valid?/2`, `initial_phase/1`

- [x] No external dependencies (pure data + pattern matching)

### Step 2: Context Fields (`lib/agent_ex/loop/context.ex`)
- [x] Add `mode` field (default `:agentic`)
- [x] Add `plan`, `plan_step_index`, `plan_steps_completed` fields
- [x] Add `human_input`, `pending_human_response` fields
- [x] Add `workspace_snapshot`, `file_reads` fields
- [x] Update `@type t` spec

- [x] Update `Context.new/1` to accept all new fields

### Step 3: ModeRouter (`lib/agent_ex/loop/stages/mode_router.ex`)
- [x] Implements full routing table from proposal §5.1
- [x] Handles all `(mode, phase, stop_reason)` combinations
- [x] Enforces phase transitions via `Phase.transition/2`
- [x] Enforces `max_turns` safety rail
- [x] Handles summary nudge logic (ported from StopReasonRouter)
- [ ] Handle callbacks (`on_response_facts`, `on_persist_turn`)

### Step 4: PlanBuilder (`lib/agent_ex/loop/stages/plan_builder.ex`)
- [x] Inject structured plan-request prompt
- [x] Handle revision pass-through
- [x] No-op when `phase != :plan`

### Step 5: PlanTracker (`lib/agent_ex/loop/stages/plan_tracker.ex`)
- [x] Detect step completion via regex patterns
- [x] Increment `plan_step_index`
- [x] Inject progress messages
- [x] Transition to `:verify` when all steps complete
- [x] Invoke `:on_step_complete` callback

### Step 6: HumanCheckpoint (`lib/agent_ex/loop/stages/human_checkpoint.ex`)
- [x] Build proposal from LLM response
- [x] Call `:on_human_input` callback
- [x] Handle `{:approve, ctx}`, `{:approve, feedback, ctx}`, `{:abort, reason}`
- [x] Pass-through when `phase == :execute`

### Step 7: VerifyPhase (`lib/agent_ex/loop/stages/verify_phase.ex`)
- [x] Inject verification prompt
- [x] No-op when `phase != :verify`

### Step 8: WorkspaceSnapshot (`lib/agent_ex/loop/stages/workspace_snapshot.ex`)
- [x] Gather git context (branch, status, recent commits)
- [x] Gather file tree (top-level)
- [x] Gather instruction files (AGENTS.md, README.md, etc.)
- [x] Gather project config (mix.exs, package.json, etc.)
- [x] Support `:on_workspace_snapshot` callback override
- [x] No-op on subsequent passes

---

## Phase 2: Profile & Entry Point

### Step 9: Profile Updates (`lib/agent_ex/loop/profile.ex`)
- [x] Add `stages(:agentic_planned)` clause (9 stages)
- [x] Add `stages(:turn_by_turn)` clause (7 stages)
- [x] Add `config(:agentic_planned)` clause
- [x] Add `config(:turn_by_turn)` clause
- [x] Update `:agentic` and `:conversational` to use `ModeRouter`

### Step 10: Entry Point Updates (`lib/agent_ex.ex`)
- [x] Add `:mode` opt to `run/1`
- [x] Map mode to profile name
- [x] Set initial phase via `Phase.initial_phase/1`
- [x] Wire new callbacks (`on_human_input`, `on_plan_created`, `on_step_complete`, `on_tool_approval`, `on_workspace_snapshot`)
- [x] Support `plan:` opt for pre-built plans

---

## Phase 3: Persistence

### Step 11: Behaviour Definitions
- [x] `AgentEx.Persistence.Transcript` behaviour
- [x] `AgentEx.Persistence.Plan` behaviour
- [x] `AgentEx.Persistence.Knowledge` behaviour
- [x] Formalize `AgentEx.Storage.Backend` behaviour

### Step 12: Local Backends
- [x] `AgentEx.Persistence.Transcript.Local` (JSONL)
- [x] `AgentEx.Persistence.Plan.Local` (JSON)
- [x] `AgentEx.Persistence.Knowledge.Local` (JSONL)

---

## Phase 4: Cleanup

### Step 13: Delete StopReasonRouter
- [x] Delete `lib/agent_ex/loop/stages/stop_reason_router.ex`
- [x] Delete `test/agent_ex/loop/stages/stop_reason_router_test.exs`
- [x] Update all references (engine.ex, llm_call.ex, tool_executor.ex, stage.ex, profile_test.exs, AGENTS.md)

### Step 14: Test Helper Additions
- [x] `mock_human_callback/1`
- [x] `build_planned_ctx/1`
- [x] `build_turn_by_turn_ctx/1`
- [x] `mock_llm_plan_response/1`

---

## Phase 5: Tests

### Step 15: Phase Tests
- [x] Transition validation per mode
- [x] Invalid transitions return error
- [x] `initial_phase/1` correctness

### Step 16: ModeRouter Tests
- [x] All routing table combinations
- [x] Phase transition side effects
- [x] Summary nudge behavior
- [x] Max turns safety rail
- [x] Plan parsing from JSON
- [x] Turn-by-turn phase transitions
- [x] Conversational mode
- [x] Unknown stop reason fallback

### Step 17: Stage Tests (deferred to V1.1)
- [-] PlanBuilder tests
- [-] PlanTracker tests
- [-] HumanCheckpoint tests
- [-] VerifyPhase tests
- [-] WorkspaceSnapshot tests

### Step 18: Persistence Backend Tests (deferred to V1.1)
- [-] Transcript local tests
- [-] Plan local tests
- [-] Knowledge local tests

### Step 19: Integration Tests (deferred to V1.1)
- [-] `agentic_planned_test.exs` — full plan → execute → verify lifecycle
- [-] `turn_by_turn_test.exs` — human approval/revision/abort flows

### Step 20: Regression
- [x] `mix test` passes clean — **118 tests, 0 failures**
