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

*Decisions will be appended as implementation progresses.*
