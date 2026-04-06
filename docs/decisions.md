# Design Decisions Log

> Records all implementation decisions made during the multi-mode loop refactor, including rationale and alternatives considered.

---

## D001: Phase State Machine — Pure Module vs gen_statem
- **Date:** 2026-04-06
- **Decision:** Use a lightweight pure-function module (`AgentEx.Loop.Phase`) with map-based transition tables. No external dependencies.
- **Rationale:** The state threads through stage functions, not a long-lived GenServer. Process-based FSMs like `gen_statem` are architecturally wrong here. The `fsm` library author's own advice: "regular data structures with pattern matching in multiclauses will serve you just fine."
- **Alternatives:** `gen_statem`, `fsm` library, `machinery` library
- **Source:** multi-mode-loop-proposal.md §3.2

---

## D002: StopReasonRouter Replacement Strategy
- **Date:** 2026-04-06
- **Decision:** Delete `StopReasonRouter` entirely and replace with `ModeRouter`. No backward compatibility layer.
- **Rationale:** This library has no existing consumers, so no migration path is needed. The `:agentic` mode's routing logic becomes a clause inside `ModeRouter`.
- **Source:** multi-mode-loop-proposal.md §2 (Design Principle 5)

---

## D003: Human-in-the-Loop via Callback
- **Date:** 2026-04-06
- **Decision:** Human input is a callback (`:on_human_input`), not a process or GenServer.
- **Rationale:** Let the host application decide how to present and collect human responses (CLI prompt, WebSocket, message queue, etc.). The loop sees it as synchronous — timeout behavior is the host's responsibility.
- **Source:** multi-mode-loop-proposal.md §2 (Design Principle 4), §4.1

---

## D004: Plan Parsing Strategy
- **Date:** 2026-04-06
- **Decision:** Prefer structured JSON output from LLM with free-text heuristic fallback.
- **Rationale:** JSON mode gives reliable parsing when available. Graceful degradation to heuristic parsing ensures compatibility with all LLM providers. If parsing fails entirely, ModeRouter falls back to `:agentic` behavior.
- **Source:** multi-mode-loop-proposal.md §5.2, §8

---

## D005: Persistence via Behaviours, Not Ash/Ecto
- **Date:** 2026-04-06
- **Decision:** Define persistence behaviours and ship filesystem-backed defaults. AgentEx does NOT depend on Ash or Ecto directly.
- **Rationale:** AgentEx is a library, not an application. Ash + ash_postgres + PostgreSQL is too heavy a requirement for every consumer. The pattern is proven by Homunculus's `DataAccess` behaviour.
- **Source:** persistence-strategy.md §2

---

## D006: Mode is Fixed at Run Time
- **Date:** 2026-04-06
- **Decision:** Mode cannot be switched mid-run in V1. Mode is set at `run/1` time and fixed for the session.
- **Rationale:** Simplifies implementation significantly. Mode switching requires complex state migration that can be added in a future version if needed.
- **Source:** multi-mode-loop-proposal.md §11

---

## D007: Tool Schema String Keys
- **Date:** 2026-04-06
- **Decision:** Continue using string keys for tool schemas everywhere. All new stages must follow this convention.
- **Rationale:** Consistency with existing codebase convention. Messages, content blocks, and LLM response maps are all string-keyed.
- **Source:** AGENTS.md (Conventions)

---

## D008: Implementation Order
- **Date:** 2026-04-06
- **Decision:** Implement in order: Phase → Context fields → ModeRouter → New stages → Profiles → Entry point. Tests alongside each step.
- **Rationale:** Each step builds on the previous. Phase and Context are foundational. ModeRouter replaces StopReasonRouter (required by all profiles). Stages are self-contained once ModeRouter exists.
- **Source:** multi-mode-loop-proposal.md §10, implementation-plan.md §1

---

## D009: Profile Stage Pipelines
- **Date:** 2026-04-06
- **Decision:**
  - `:agentic`: ContextGuard → ProgressInjector → LLMCall → ModeRouter → ToolExecutor → CommitmentGate
  - `:agentic_planned`: WorkspaceSnapshot → ContextGuard → PlanBuilder → ProgressInjector → LLMCall → ModeRouter → ToolExecutor → PlanTracker → CommitmentGate
  - `:turn_by_turn`: WorkspaceSnapshot → ContextGuard → LLMCall → ModeRouter → HumanCheckpoint → ToolExecutor → CommitmentGate
  - `:conversational`: ContextGuard → LLMCall → ModeRouter
- **Rationale:** Each mode composes from the same stage primitives (Design Principle 1). WorkspaceSnapshot only in modes that benefit from workspace context. No ProgressInjector in turn_by_turn (human is the progress mechanism).
- **Source:** multi-mode-loop-proposal.md §6

---

## D010: Step Completion Detection
- **Date:** 2026-04-06
- **Decision:** LLM self-reports step completion via prompt engineering. After N turns per step, prompt LLM to confirm (fallback).
- **Rationale:** Direct and simple. The ContinuationDetector patterns from Homunculus can supplement detection, but primary strategy is prompt engineering to avoid brittle regex matching.
- **Source:** multi-mode-loop-proposal.md §5.3, porting-analysis.md §1.4

---

## D011: Per-Tool Output Clipping via Module Attribute
- **Date:** 2026-04-06
- **Decision:** ToolExecutor clips tool output based on per-tool byte limits defined in a `@default_max_output_bytes` module attribute. Host overrides via `Process.put(:tool_max_output_bytes, map)`.
- **Rationale:** Prevents single large file reads from blowing context. The defaults (50KB for `read_file`, 1MB for `bash`, 10KB for `list_files`) cover the common cases. `Process.put` allows per-request overrides without changing the stage API.
- **Alternatives:** Config-based limits, per-tool callback. Module attribute + Process dictionary is simplest and has zero API surface change.

---

## D012: File-Read Deduplication Tracking
- **Date:** 2026-04-06
- **Decision:** ToolExecutor tracks `read_file` calls in `ctx.file_reads` (path → %{hash, last_read_turn}). Actual deduplication (replacing older reads with summaries) deferred to ContextGuard integration.
- **Rationale:** The tracking is cheap and unobtrusive. The compaction policy (which older reads to summarize) belongs in ContextGuard, not ToolExecutor. This keeps the stages single-responsibility.

---

## D013: ContinuationDetector — Pure Regex, No ML
- **Date:** 2026-04-06
- **Decision:** Port ContinuationDetector from Homunculus using regex patterns only. Five detection categories: step_complete, task_complete, continuation, blocker, summary.
- **Rationale:** Regex is sufficient for the structured output patterns LLMs produce. No NLP dependency needed. The `detect/2` function returns confidence scores for optional filtering. Question-ending text (`?`) is excluded from task_complete to reduce false positives.
- **Source:** porting-analysis.md §1.4 (ContinuationDetector)

---

## D014: ContextCompression — Two-Tier Strategy
- **Date:** 2026-04-06
- **Decision:** Port the two-tier truncation/summarization pattern from Homunculus. Truncate when context is <2× budget (cheap, fast). LLM summarize when ≥2× budget (expensive but thorough). Fall back to truncation on LLM error.
- **Rationale:** The 2× threshold balances cost vs quality. Simple truncation is always available as a fallback. The LLM summarization uses the `llm_chat` callback with `model_tier: "lightweight"` to minimize cost.
- **Source:** porting-analysis.md §15.1.3 (MemoryManager.optimize_context)

---

## D015: LLMSemaphore — Process-Based Concurrency
- **Date:** 2026-04-06
- **Decision:** Port LLMSemaphore as a GenServer with automatic permit release on process crash via `Process.monitor/1`.
- **Rationale:** Subagents (V2.0) will need bounded concurrency. The semaphore is the foundation. Automatic crash cleanup prevents deadlocks when child processes die. FIFO ordering ensures fairness.
- **Source:** porting-analysis.md §15.1.2 (SCE semaphore)

---

## D016: Persistence Backend JSON Atom/String Normalization
- **Date:** 2026-04-06
- **Decision:** `Plan.Local.list_plans/2` counts completed steps using `status == :complete or status == "complete"`. Does not normalize at read time.
- **Rationale:** Jason serializes atoms as strings, so a round-trip through JSON turns `:complete` into `"complete"`. Normalizing at read time would require knowing which fields are atom-typed, which is fragile. Accepting both is pragmatic for V1.1. A future V2 task should add a proper serialization layer.
- **Source:** Discovered during persistence backend testing.

---

## D017: Integration Tests Test Stage Interactions, Not Full Engine Loops
- **Date:** 2026-04-06
- **Decision:** Integration tests for `:agentic_planned` and `:turn_by_turn` test stage interactions (PlanBuilder → ModeRouter → PlanTracker) rather than full `Engine.run` pipelines.
- **Rationale:** `Engine.run` is a single-pass pipeline with no built-in looping. Multi-turn behavior requires `reentry_pipeline` which is set up by the host application, not the engine. Testing individual stage interactions validates the integration without fighting the engine's single-pass nature. CommitmentGate intercepts uncommitted "I will..." text, making full-pipeline tests fragile.
- **Source:** Discovered during integration test writing.
