# Implementation Progress

> Tracks multi-mode loop implementation. See [decisions.md](./decisions.md) for design decisions log.

## Status: V2.1 COMPLETE

---

## V1.0 — COMPLETE

### Phase 1: Core Infrastructure
- [x] Phase state machine (`lib/agentic/loop/phase.ex`)
- [x] Context fields (`lib/agentic/loop/context.ex`)
- [x] ModeRouter (`lib/agentic/loop/stages/mode_router.ex`)
- [x] PlanBuilder (`lib/agentic/loop/stages/plan_builder.ex`)
- [x] PlanTracker (`lib/agentic/loop/stages/plan_tracker.ex`)
- [x] HumanCheckpoint (`lib/agentic/loop/stages/human_checkpoint.ex`)
- [x] VerifyPhase (`lib/agentic/loop/stages/verify_phase.ex`)
- [x] WorkspaceSnapshot (`lib/agentic/loop/stages/workspace_snapshot.ex`)

### Phase 2: Profile & Entry Point
- [x] Profile updates (4 profiles)
- [x] Entry point updates (`run/1`, `resume/1`)

### Phase 3: Persistence
- [x] Transcript behaviour + local backend
- [x] Plan behaviour + local backend
- [x] Knowledge behaviour + local backend
- [x] Storage.Backend behaviour

### Phase 4: Cleanup
- [x] Delete StopReasonRouter
- [x] Test helper additions

---

## V1.1 — COMPLETE

### Deferred V1.0 Tests
- [x] PlanBuilder unit tests
- [x] PlanTracker unit tests
- [x] HumanCheckpoint unit tests
- [x] VerifyPhase unit tests
- [x] WorkspaceSnapshot unit tests
- [x] Persistence backend tests
- [x] agentic_planned integration test
- [x] turn_by_turn integration test

### V1.1 Enhancements
- [x] Per-tool output clipping in ToolExecutor (`read_file` → 50KB, `bash` → 1MB, `list_files` → 10KB)
- [x] File-read deduplication tracking in ToolExecutor (`ctx.file_reads`)
- [x] ContinuationDetector port from Homunculus
- [x] ContextCompression two-tier truncate/summarize port from Homunculus
- [x] LLMSemaphore bounded concurrency port from SCE
- [-] Recollect Knowledge backend (deferred — requires Recollect DB)

---

## V1.2 — COMPLETE

- [x] LLMCall restructured with stable/volatile message separation
- [x] `cache_control` param with `stable_hash` and `prefix_changed` sent to `llm_chat`
- [x] `stable_prefix_hash` context field (tracks when prefix changes)
- [x] Hash computed from system prompt + tool definitions

---

## V1.3 — COMPLETE

- [x] TranscriptRecorder stage (`lib/agentic/loop/stages/transcript_recorder.ex`)
- [x] Records `llm_response` and `tool_call` events via transcript backend
- [x] No-op when no `transcript_backend` callback configured
- [x] Added to all 4 profiles (after ModeRouter)
- [x] `Agentic.resume/1` with transcript reconstruction

---

## V2.0 — COMPLETE

- [x] Context fields: `subagent_depth`, `subagent_budget`, `parent_session_id`
- [x] `Agentic.Subagent.Coordinator` GenServer (per-workspace, Registry-backed)
- [x] `Agentic.Subagent.CoordinatorSupervisor` (DynamicSupervisor, lazy start)
- [x] `Agentic.Subagent.DelegateTask` tool definition + execution
- [x] `delegate_task` tool wired into `Tools.definitions/0` and `Tools.execute/3`
- [x] Max concurrent subagents: 5 per workspace
- [x] Max subagent nesting depth: 3
- [x] Default max_turns per subagent: 20 (configurable, max 50)

---

## V2.1 — COMPLETE

- [x] `tool_permissions` context field (`%{tool_name => :auto | :approve | :deny}`)
- [x] `:on_tool_approval` callback
- [x] Permission check in ToolExecutor before circuit breaker
- [x] Wired `tool_permissions` option in `Agentic.run/1`

---

## V2.2 — COMPLETE

- [x] CLI agent protocols (Claude Code, OpenCode, Codex)
- [x] ACP (Agent Client Protocol) support
- [x] Protocol Registry with auto-detection
- [x] Tool activation system (budget-limited promotion)
- [x] Model router with manual and auto selection modes
- [x] Strategy layer with Default and Experiment strategies
- [x] `AgentProtocol` behaviour for custom backends

---

## Future

- Recollect Knowledge backend (deferred — requires Recollect DB)
- Async subagent execution
- Mode switching mid-run
