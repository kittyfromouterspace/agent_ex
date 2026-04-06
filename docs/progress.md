# Implementation Progress

> Tracks multi-mode loop implementation. See [decisions.md](./decisions.md) for design decisions log.

## Status: V1.1 COMPLETE (235 tests, 0 failures)

- [ ] Not started
- [~] In progress
- [x] Complete
- [-] Skipped / deferred

---

## V1.0 — COMPLETE

### Phase 1: Core Infrastructure
- [x] Phase state machine (`lib/agent_ex/loop/phase.ex`)
- [x] Context fields (`lib/agent_ex/loop/context.ex`)
- [x] ModeRouter (`lib/agent_ex/loop/stages/mode_router.ex`)
- [x] PlanBuilder (`lib/agent_ex/loop/stages/plan_builder.ex`)
- [x] PlanTracker (`lib/agent_ex/loop/stages/plan_tracker.ex`)
- [x] HumanCheckpoint (`lib/agent_ex/loop/stages/human_checkpoint.ex`)
- [x] VerifyPhase (`lib/agent_ex/loop/stages/verify_phase.ex`)
- [x] WorkspaceSnapshot (`lib/agent_ex/loop/stages/workspace_snapshot.ex`)

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
- [x] PlanBuilder unit tests (7 tests)
- [x] PlanTracker unit tests (14 tests)
- [x] HumanCheckpoint unit tests (11 tests)
- [x] VerifyPhase unit tests (7 tests)
- [x] WorkspaceSnapshot unit tests (7 tests)
- [x] Persistence backend tests (24 tests)
- [x] agentic_planned integration test (8 tests)
- [x] turn_by_turn integration test (12 tests)

### V1.1 Enhancements
- [x] Per-tool output clipping in ToolExecutor (`read_file` → 50KB, `bash` → 1MB, `list_files` → 10KB)
- [x] File-read deduplication tracking in ToolExecutor (`ctx.file_reads`)
- [x] ContinuationDetector port from Homunculus (20 tests)
- [x] ContextCompression two-tier truncate/summarize port from Homunculus (8 tests)
- [x] LLMSemaphore bounded concurrency port from SCE (7 tests)
- [-] Mneme Knowledge backend (deferred — requires Mneme DB)

---

## Next: V1.2

- Prompt prefix / cache awareness (stable/volatile separation)
- LLMCall restructured with cache boundary markers
- `stable_prefix_hash` context field

## Future: V2.0

- Bounded subagents + ported Coordinator architecture
- `delegate_task` tool, LLMSemaphore for subagent depth
- Tool permission gating (V2.1)
