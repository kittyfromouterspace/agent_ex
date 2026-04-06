# Cross-Codebase Porting Analysis

> Companion to [Main Proposal](./multi-mode-loop-proposal.md). Identifies existing modules, patterns, and code from **homunculus** and **strategic_change_engine** (SCE) that can be ported to AgentEx.

---

## Source Codebases

| Codebase | Structure | Relationship to AgentEx |
|---|---|---|
| **homunculus** | 4-app Elixir umbrella (`homunculus_agent`, `homunculus_core`, `homunculus_shared`, `homunculus_web`) | Uses `agent_ex` as a GitHub-sourced dependency. The `homunculus_agent` app bridges to AgentEx via `AgentExCallbacks` and `DataAccess` behaviour. |
| **strategic_change_engine** (SCE) | Single Phoenix/Ash app with 9 specialized agents | Uses `mneme` as a dependency. Shares the same Ash config block as homunculus. |

---

## 1. Directly Portable: High Value

### 1.1 Subagent System → Homunculus `Coordinator` + `SubAgentTools`

**Addresses:** Enhancement E6 (Bounded Subagents)

| Source File | Module | Lines |
|---|---|---|
| `homunculus/apps/homunculus_agent/lib/homunculus/agent/coordinator.ex` | `Homunculus.Agent.Coordinator` | 430 |
| `homunculus/apps/homunculus_agent/lib/homunculus/agent/sub_agent_tools.ex` | `Homunculus.Agent.SubAgentTools` | 147 |
| `homunculus/apps/homunculus_agent/lib/homunculus/agent/coordinator_supervisor.ex` | `Homunculus.Agent.CoordinatorSupervisor` | 57 |
| `homunculus/apps/homunculus_agent/lib/homunculus/agent/native_loop/tools/sub_agent.ex` | `Homunculus.Agent.NativeLoop.Tools.SubAgent` | 109 |

**What exists:** Full production sub-agent lifecycle:
- 4 tools: `spawn_sub_agent`, `check_sub_agent`, `list_sub_agents`, `stop_sub_agent`
- Per-workspace `Coordinator` GenServer registered via `Registry` with lazy start (`CoordinatorSupervisor.ensure_coordinator/1`)
- Max 5 concurrent sub-agents per workspace
- Process monitoring (`Process.monitor/1`) with automatic cleanup on `:DOWN`
- Result delivery to parent via `GenServer.cast(parent_pid, {:send_internal, result})`
- Auto-shutdown when idle (`:transient` restart, 30-second delayed `:check_idle_shutdown`)
- Sub-session ID generation: `sub-<parent_session_id>-<random_4_bytes_hex>`

**Key code to study:**
- `Coordinator.handle_call({:spawn_sub_agent, params}, ...)`: Concurrency check → session ID generation → `Agent.Supervisor.start_agent/3` → monitor → send task prompt
- `Coordinator.handle_info({:DOWN, ref, ...})`: Failure detection → report to parent
- `SubAgent.definitions/0`: Tool schemas nearly identical to the proposal's `delegate_task` schema

**Porting path:**
1. Extract the coordination pattern (spawn → monitor → collect result → deliver to parent)
2. Replace `Agent.Supervisor.start_agent/3` with `AgentEx.run/1` calls
3. Replace `DataAccess.subscribe` / `Registry.whereis` with a callback-based approach
4. Replace the ad-hoc `@max_concurrent 5` count with the `LLMSemaphore` pattern from SCE

**Effort:** Medium. Architecture is right; requires decoupling from Homunculus infrastructure.

---

### 1.2 Workspace Snapshot → Homunculus `ContextAssembler` + `Identity`

**Addresses:** Enhancement E1 (Workspace Snapshot Stage)

| Source File | Module | Lines |
|---|---|---|
| `homunculus/apps/homunculus_agent/lib/homunculus/workspace/context_assembler.ex` | `Homunculus.Workspace.ContextAssembler` | 520 |
| `homunculus/apps/homunculus_shared/lib/homunculus/workspace/identity.ex` | `Homunculus.Workspace.Identity` | 76 |

**What exists:**
- Budget-aware prompt assembly: `@system_prompt_fraction 0.25` of context window
- `compute_max_chars/1`: Derives char budget from `context_window` tokens via `@chars_per_token 3.5`
- Priority-ordered section building: identity → soul → user → agents → tools → memory → knowledge
- `truncated_section/3`: Budget-aware truncation with `[... truncated for context budget ...]` markers
- `estimate_tool_tokens/1`: Token estimation for tool schemas (~40 chars overhead per tool)
- `tool_activation_budget/2`: Max additional tools within 10% of context window
- 60/40 memory/knowledge budget split
- `Identity.read_all_files/1`: Reads all workspace files into a map

**What the proposal additionally needs (not in homunculus):**
- Git branch/status/commits gathering
- File tree directory listing
- Project config detection (mix.exs, package.json, etc.)

**Porting path:** The budget-aware assembly and truncation logic (`compute_max_chars`, `truncated_section`, `estimate_tool_tokens`) is self-contained with no external dependencies. Port those functions directly. Add new `gather_git_context/1` and `gather_file_tree/1` gatherers.

**Effort:** Low.

---

### 1.3 Context Compression → Homunculus `MemoryManager` + SCE `Summarizer`

**Addresses:** Enhancement E3 (Output Clipping and Deduplication)

| Source File | Module | Key Function |
|---|---|---|
| `homunculus/apps/homunculus_agent/lib/homunculus/agent/memory_manager.ex` | `Homunculus.Agent.MemoryManager` | `optimize_context/3` (lines 100-121) |
| `strategic_change_engine/lib/strategic_change_engine/chat/summarizer.ex` | `StrategicChangeEngine.Chat.Summarizer` | `summarize_conversation/2` (179 lines) |

**What exists:**

*Homunculus `MemoryManager.optimize_context/3`:* Two-tier strategy:
- Content ≤ budget → pass through unchanged
- Content < 2× budget → truncate with `String.slice`
- Content ≥ 2× budget → LLM-summarize with budget-aware prompt, fall back to truncation on error
- Self-contained `summarize_with_llm/3` function (lines 138-189)

*SCE `Summarizer`:* Structured conversation compression:
- Threshold check: `total_tokens > 8000`
- Summarizes oldest half of messages via LLM
- Structured output: `## Key Actions / ## Artifacts Created / ## User Goals / ## Important Context`
- Stores `ConversationSummary` records with token savings metadata

**Porting path:** The two-tier truncation/summarization pattern is directly reusable in `ContextGuard`. The `Summarizer`'s structured output format is a good template for LLM-based compaction. Neither handles file-read deduplication — that needs new code.

**Effort:** Low for clipping/summarization. Medium for deduplication (no existing pattern to port).

---

### 1.4 Plan Detection → Homunculus `ContinuationDetector`

**Addresses:** ModeRouter (§5.1), PlanTracker (§5.3)

| Source File | Module | Lines |
|---|---|---|
| `homunculus/apps/homunculus_agent/lib/homunculus/agent/continuation_detector.ex` | `Homunculus.Agent.ContinuationDetector` | 210 |

**What exists:** Pure-function static analysis with zero dependencies:
- 5 detection categories: `:unfinished_plan`, `:continuation_intent`, `:error_recovery`, `:task_markers`, `:commitment`
- Returns `{:continue, [reason]}` or `:done`
- False positive filtering via `@negative_patterns`
- `:steps` option prevents false signals when agent was actively using tools

**Porting path:**
- `@plan_patterns` can be reused inside `PlanTracker` to detect step completion
- `:continuation_intent` and `:unfinished_plan` signals can inform `ModeRouter` routing decisions
- The false-positive filtering logic is directly applicable
- Directly portable: zero dependencies, pure functions

**Effort:** Very low. Drop-in module.

---

### 1.5 Callback Architecture → Homunculus `AgentExCallbacks`

**Addresses:** New Callbacks (Main Proposal §4)

| Source File | Module | Lines |
|---|---|---|
| `homunculus/apps/homunculus_agent/lib/homunculus/agent/agent_ex_callbacks.ex` | `Homunculus.Agent.AgentExCallbacks` | 183 |

**What exists:** 10-callback map pattern bridging the generic AgentEx loop to host-specific subsystems:

| Callback | Purpose |
|---|---|
| `llm_chat` | LLM completion calls |
| `execute_tool` | Run builtin tools |
| `on_event` | Stream events to caller |
| `on_response_facts` | Extract facts from LLM response |
| `on_tool_facts` | Extract facts from tool results |
| `on_persist_turn` | Save conversation turns |
| `get_tool_schema` | Get schema for external tools |
| `search_tools` | Discover tools by query |
| `execute_external_tool` | Run MCP/integration tools |
| `get_secret` | Retrieve secrets |

**Key pattern:** Factory functions capture workspace/user context in closures. Async operations use `Task.start`. All callbacks are optional — `nil` values handled gracefully.

This demonstrates exactly the pattern for the proposal's new callbacks (`on_human_input`, `on_plan_created`, `on_step_complete`, `on_tool_approval`).

**Effort:** Very low. Pattern is proven and directly applicable.

---

## 2. Partially Applicable: Medium Value

### 2.1 Tool Permission Gating → SCE `ToolRegistry.tools_for_agent/3`

**Addresses:** Enhancement E5 (Tool Permission and Approval Gating)

| Source File | Module |
|---|---|
| `strategic_change_engine/lib/strategic_change_engine/llm/tool_registry.ex` | `StrategicChangeEngine.LLM.ToolRegistry` |

Static per-agent-type tool scoping (`:orchestrator` → read-only, `:domain_mapper` → CRUD, etc.). The `tools_for_agent/3` dispatch pattern is a starting point for mode-dependent tool sets. Limitations: role-based only, no runtime approval flow.

**Effort:** Medium. Pattern is right but needs a new permission-checking layer.

---

### 2.2 Session Persistence → SCE `Conversation` + `Message` Resources

**Addresses:** Enhancement E4 (Full Transcript and Session Resumption)

The data model (sequenced messages with role/content/tokens/metadata, `provenance` field) is reusable. The `Message` resource has `provenance: :human_authored | :agent_authored | :co_authored | :human_reviewed` — directly applicable for `:turn_by_turn` mode.

**Limitation:** PostgreSQL-backed via Ash. Too heavy to port directly. The `Summarizer.get_latest_summary/2` pattern for compressed conversation replay maps to the session resumption flow.

**Effort:** Medium. Data model reusable; storage backend needs new implementation.

---

### 2.3 Concurrency Control → SCE `LLMSemaphore`

**Addresses:** Enhancement E6 (Subagent concurrency management)

| Source File | Module | Lines |
|---|---|---|
| `strategic_change_engine/lib/strategic_change_engine/ai/llm_semaphore.ex` | `StrategicChangeEngine.AI.LLMSemaphore` | 99 |

GenServer-based concurrency limiter with `with_permit/1`, automatic permit release on crash via `Process.monitor/1`, FIFO queue. Zero external dependencies. Directly usable for limiting concurrent subagent LLM calls.

**Effort:** Very low. Self-contained module.

---

### 2.4 Per-Type Context Assembly → SCE `ContextBuilder`

**Addresses:** Enhancement E1 (Workspace Snapshot)

| Source File | Module | Lines |
|---|---|---|
| `strategic_change_engine/lib/strategic_change_engine/ai/context_builder.ex` | `StrategicChangeEngine.AI.ContextBuilder` | 1363 |

Rich per-agent-type context assembly with different context views per agent role. The `build_context/3` dispatch pattern (switch on agent type) maps to the proposal's mode-dependent context building.

**Effort:** Medium. Pattern reusable; context sources need replacement for code workspace domain.

---

## 3. Not Directly Portable — Must Be Built New

| Need | What's Missing |
|---|---|
| Mode-aware routing table | Neither codebase has execution-mode routing based on `(mode, phase, stop_reason)` tuples |
| Phase state machine | Neither has multi-phase execution within a session |
| Human checkpoint stage | No agent-pauses-for-approval pattern. SCE's artifact save is user-initiated |
| PlanBuilder / PlanTracker | No structured plan data type. `ContinuationDetector` detects plan language but doesn't track structured steps |
| Cache boundary markers | Neither implements LLM provider cache APIs |
| File-read deduplication | Neither tracks repeated file reads |

---

## 4. Recommended Porting Priority

| Priority | Module to Port | Source | Proposal Section | Effort |
|---|---|---|---|---|
| 1 | `ContinuationDetector` | Homunculus | ModeRouter + PlanTracker | Very Low |
| 2 | `AgentExCallbacks` callback-map pattern | Homunculus | New Callbacks | Very Low |
| 3 | `LLMSemaphore` | SCE | Subagent concurrency | Very Low |
| 4 | `MemoryManager.optimize_context/3` | Homunculus | Context compression | Low |
| 5 | `ContextAssembler` budget-aware assembly | Homunculus | Workspace Snapshot | Low |
| 6 | `Summarizer` structured compression | SCE | Context compression | Low |
| 7 | `Coordinator` + `SubAgentTools` architecture | Homunculus | Bounded Subagents | Medium |
| 8 | `ToolRegistry.tools_for_agent/3` dispatch | SCE | Tool permissions | Medium |
| 9 | `ContextBuilder` per-type assembly pattern | SCE | Workspace Snapshot | Medium |
| 10 | `Conversation` + `Message` data model | SCE | Session transcript | Medium |

Priorities 1-3 should be ported in V1.0 alongside the core multi-mode pipeline. Priorities 4-6 align with V1.1. Priority 7 is the major V2.0 effort. Priorities 8-10 can be tackled incrementally.
