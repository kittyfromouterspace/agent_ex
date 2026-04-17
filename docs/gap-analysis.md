# Gap Analysis — Agentic Multi-Mode Loop

> Companion to [Main Proposal](./multi-mode-loop-proposal.md). See also [Porting Analysis](./porting-analysis.md), [Persistence Strategy](./persistence-strategy.md), [Implementation Plan](./implementation-plan.md).

Source: [Components of a Coding Agent](https://magazine.sebastianraschka.com/p/components-of-a-coding-agent) — Sebastian Raschka identifies six building blocks of a coding harness. Below is a gap analysis comparing Agentic's current state (including the multi-mode proposal) against each component.

---

## Component 1: Live Repo Context

**What it means:** Before doing any work, the harness gathers a workspace summary — git branch, file tree, instruction files (AGENTS.md, README), project config — so the agent starts with "stable facts" rather than zero context.

**What Agentic has today:** The workspace path is passed to `run/1` and used in a generic system prompt: `"You are a helpful AI assistant working in #{workspace}."` (see `lib/agentic.ex:84`). The `Workspace.Service` module scaffolds workspaces with identity files, but nothing is automatically gathered or injected at session start.

**Gap:**
- No automatic repo snapshot at session start (git branch, status, recent commits)
- No file tree summary injected into the initial context
- No reading of instruction files (AGENTS.md, README, CLAUDE.md, etc.) into the system prompt
- The agent starts blind and must discover the repo layout through tool calls, wasting turns

**Impact on multi-mode proposal:** This hurts `:agentic_planned` most — the plan quality depends on the LLM understanding the repo upfront. Also hurts `:turn_by_turn` because the human has to repeat context the agent should already know.

**Proposed enhancement:** `WorkspaceSnapshot` stage (see Main Proposal §5.6). Uses budget-aware assembly patterns from `Homunculus.Workspace.ContextAssembler`.

---

## Component 2: Prompt Shape and Cache Reuse

**What it means:** The harness separates the prompt into a stable prefix (instructions, tool schemas, workspace summary — rarely changes) and a volatile suffix (recent transcript, current request — changes every turn). The stable prefix can be cached by the LLM provider, avoiding re-processing on every turn.

**What Agentic has today:** The full `messages` list is rebuilt and sent to `llm_chat` every turn as a flat list. There is no concept of a stable prefix vs volatile suffix. No cache boundary markers are passed to the LLM provider.

**Gap:**
- No prompt prefix/suffix separation
- No cache boundary hints passed through `llm_chat` params (e.g., Anthropic cache_control, OpenAI cached tokens)
- Tool schemas and system prompt are re-processed by the LLM on every turn, wasting tokens and latency
- For long sessions, this is a significant cost and speed penalty

**Impact on multi-mode proposal:** All modes suffer, but `:agentic_planned` and `:agentic` with long sessions are most affected because they make the most LLM calls.

**Proposed enhancement (E2):** Restructure `LLMCall` to separate `params` into `:stable` prefix (system prompt + workspace snapshot + tool definitions) and `:volatile` suffix (recent transcript). Pass cache boundary hints via a `cache_control` key in params. The `llm_chat` callback translates these into provider-specific API params.

New context field: `stable_prefix_hash: String.t() | nil` — tracks if prefix changed since last call.

---

## Component 3: Tool Access and Use

**What it means:** Structured tools with validation, path sandboxing, approval gating, and bounded output. The harness checks "is this a known tool?", "are arguments valid?", "does this need user approval?", "is the path inside the workspace?" before executing.

**What Agentic has today:** This is the strongest area. Structured tool schemas (string-keyed), `Tools.execute/3` dispatch, CircuitBreaker (`lib/agentic/circuit_breaker.ex`), path traversal protection in `resolve_path/2`, and output truncation for bash (`@max_output_bytes`). The `Gateway` module handles lazy tool discovery and activation with an LRU budget.

**Gap:**
- No per-tool approval gating (the host can't say "approve bash commands but auto-approve reads")
- No tool-level permission configuration (e.g., "this session can't run bash")
- File read output has no size limit — a 10MB file enters the context untruncated

**Impact on multi-mode proposal:** Minor. The `:turn_by_turn` mode partially addresses approval gating via `HumanCheckpoint`, but it's proposal-level, not per-tool.

**Proposed enhancement (E5):** Add `tool_permissions` context field and `:on_tool_approval` callback. See Main Proposal §4.4.

---

## Component 4: Minimizing Context Bloat

**What it means:** Three strategies: (a) clip large outputs, (b) deduplicate repeated file reads in the transcript, (c) compress the transcript with recency weighting (recent events kept rich, older events compressed aggressively).

**What Agentic has today:** `ContextGuard` handles compaction — when context exceeds 80%, it summarizes older messages into a deterministic handoff message. But the summarization is crude (rule-based, first 200 chars of each message, tool names listed). No LLM-based summarization.

**Gap:**
- **No output clipping** on `read_file` (bash has `@max_output_bytes`, but file reads don't)
- **No deduplication** — if the agent reads `lib/foo.ex` three times, all three full copies stay in messages
- **No recency-weighted compression** — compaction treats all old messages equally
- **No LLM-based summarization** — the compact summary is rule-based and loses nuance
- **No per-message size budget** — a single large file read can blow the context

**Impact on multi-mode proposal:** This is the most impactful gap. `:agentic_planned` mode will make many more tool calls per session (plan + execute + verify), so context bloat will be severe.

**Proposed enhancement (E3):**

*Per-source output clipping:* Add `max_output_bytes` config per tool type (defaults: `read_file` → 50KB, `bash` → 1MB already exists, `list_files` → 10KB). When `ToolExecutor` stores tool results, clip outputs that exceed the budget and append a `[truncated at N bytes, original M bytes]` marker.

*File read deduplication:* Track `read_file` calls in `ctx.file_reads`. On compaction, replace older file read results with: `"[File lib/foo.ex was read at turn 3 (last modified before read). Current content may differ.]"`. Keep only the most recent read of each file at full fidelity.

*LLM-based summarization:* Port the two-tier strategy from `Homunculus.Agent.MemoryManager.optimize_context/3` — truncate if <2× budget, LLM-summarize if ≥2× budget. See [Porting Analysis §15.1.3](./porting-analysis.md#1513-context-compression--homunculus-memorymanageroptimize_context--sce-summarizer).

---

## Component 5: Structured Session Memory

**What it means:** Two separate storage layers: (a) a full transcript (every user request, tool output, LLM response — stored durably as JSON/JSONL) and (b) working memory (small, distilled state maintained explicitly by the agent). Sessions are resumable — close the agent, reopen it, continue where you left off.

**What Agentic has today:** `ContextKeeper` provides in-process working memory (facts + key-value working set) with TTL support and fact supersession. On termination, it flushes to `MEMORY.md`. The `Memory` tools provide `memory_query`/`memory_write`/`memory_note`/`memory_recall` backed by callbacks to an external knowledge store. But there is no full transcript storage and no session resumption.

**Gap:**
- **No full transcript** — once a session ends, the complete history is gone
- **No session resumption** — `Agentic.run/1` is fire-and-forget; no way to continue a previous session
- **No durable session files** — everything is in-process (ContextKeeper is a GenServer)
- Working memory (`ContextKeeper`) is lost on crash (only flushes to `MEMORY.md` on graceful terminate)

**Impact on multi-mode proposal:** `:agentic_planned` is most affected — if a long planned session crashes mid-step, all progress and plan state is lost. `:turn_by_turn` also benefits from resumption since the human may want to close and return.

**Proposed enhancement (E4):** See [Persistence Strategy](./persistence-strategy.md) for the `Agentic.Persistence.Transcript` behaviour and session resumption design.

---

## Component 6: Delegation with Bounded Subagents

**What it means:** The main agent can spawn subagents for side tasks (e.g., "find which file defines this symbol" or "run these tests"). Subagents inherit enough context to be useful but run within tighter boundaries (read-only, restricted recursion depth, smaller context budget). This parallelizes work and keeps the main agent's context focused.

**What Agentic has today:** Zero support. No subagent spawning, no delegation, no parallel execution. Every task runs through the single main pipeline.

**Gap:**
- No subagent primitive
- No way to spawn a bounded child session
- No parallel execution of independent tasks
- The main agent carries every thread of work in its own context, accelerating bloat

**Impact on multi-mode proposal:** This is the biggest architectural gap for `:agentic_planned`. A plan step like "run tests while investigating the source of the bug" would benefit enormously from a subagent doing the test run while the main agent continues investigating.

**Proposed enhancement (E6):** Port the `Coordinator` + `SubAgentTools` architecture from homunculus. See [Porting Analysis §15.1.1](./porting-analysis.md#1511-subagent-system--homunculus-coordinator--subagenttools). The `delegate_task` tool spawns a new `Agentic.run/1` call with reduced `max_turns`, optional read-only tools, and a cost budget carved from the parent's remaining budget.

New context fields: `subagent_depth: integer()`, `subagent_budget: float() | nil`, `parent_session_id: String.t() | nil`.

Synchronous in V1 (main agent blocks until subagent completes). Async in V2.
