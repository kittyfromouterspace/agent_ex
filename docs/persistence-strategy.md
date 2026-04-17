# Persistence Strategy — Agentic Multi-Mode Loop

> Companion to [Main Proposal](./multi-mode-loop-proposal.md). Defines persistence behaviours, Recollect integration, and host application integration guide.

---

## 1. Current State

Agentic has **no database**. The `ecto_sql` and `postgrex` entries in `mix.exs` are declared but never used — no Repo module, no schemas, no migrations, no Ecto imports anywhere in the codebase. All storage is filesystem-backed via a clean delegation pattern:

```
Agentic.Storage.Context  (facade — resolves backend by atom, delegates all ops)
    └── Agentic.Storage.Local  (concrete — pure File.* calls, zero deps)
```

The backend contract (8 functions: `read`, `write`, `exists?`, `dir?`, `ls`, `rm_rf`, `mkdir_p`, `materialize_local`) is enforced by convention, not a `@behaviour`. See `lib/agentic/storage/context.ex` and `lib/agentic/storage/local.ex`.

---

## 2. Decision: Behaviour-Based Persistence, Not Ash

**Agentic will NOT depend on Ash (or Ecto) directly.** Instead, it defines persistence behaviours and ships filesystem-backed defaults. Host applications provide implementations backed by their own infrastructure (Ash, Ecto, or anything else).

**Rationale:**

1. **Agentic is a library, not an application.** Ash + ash_postgres + PostgreSQL is a heavy requirement to impose on every consumer.
2. **The pattern is proven.** Homunculus's `DataAccess` behaviour (~80 callbacks) demonstrates that the agent runtime stays clean while the host provides heavy infrastructure. Agentic's existing `Storage.Context` already does this for storage operations.
3. **No shared resource shapes.** The host projects' Ash resources (User, Workspace, etc.) are application-level, not agent-runtime resources. Agentic's needs (plans, transcripts, knowledge entries) are structurally different.

---

## 3. Integration Landscape

Both integration targets use **Ash Framework** extensively:

| Aspect | Homunculus | Strategic Change Engine |
|---|---|---|
| Ash resources | 38 across 9 domains | ~35 across 9 domains |
| Data layer | `AshPostgres` for all resources | `AshPostgres` for all resources |
| Agent-to-DB coupling | **Decoupled** via `DataAccess` behaviour | **Direct** — 101 `Ash.Changeset` call sites |
| Ash config block | Identical to SCE | Identical to homunculus |

Key: **Homunculus already decouples its agent runtime from Ash.** The `homunculus_agent` app never imports Ash. This is the proven pattern for Agentic.

---

## 4. Behaviour Definitions

### 4.1 `Agentic.Storage.Backend` (formalize existing contract)

Extracts the implicit 8-function contract from `Storage.Local` into a formal `@behaviour`:

```elixir
@callback read(config :: map(), path :: String.t()) ::
  {:ok, String.t()} | {:error, term()}

@callback write(config :: map(), path :: String.t(), content :: String.t()) ::
  :ok | {:error, term()}

@callback exists?(config :: map(), path :: String.t()) :: boolean()

@callback dir?(config :: map(), path :: String.t()) :: boolean()

@callback ls(config :: map(), path :: String.t()) ::
  {:ok, [String.t()]} | {:error, term()}

@callback rm_rf(config :: map(), path :: String.t()) :: :ok

@callback mkdir_p(config :: map(), path :: String.t()) ::
  :ok | {:error, term()}

@callback materialize_local(config :: map(), path :: String.t()) ::
  {:ok, String.t()} | {:error, term()}
```

`Agentic.Storage.Local` becomes the reference `@behaviour` implementation. `Storage.Context` gains compile-time enforcement.

---

### 4.2 `Agentic.Persistence.Transcript`

**Addresses:** Enhancement E4 (Full Transcript and Session Resumption)

Append-only session event log. The `:local` implementation writes JSONL files to `<workspace>/.agentic/sessions/<session_id>.jsonl`.

```elixir
@callback append(session_id :: String.t(), event :: map(), opts :: keyword()) ::
  :ok | {:error, term()}

@callback load(session_id :: String.t(), opts :: keyword()) ::
  {:ok, [map()]} | {:error, :not_found} | {:error, term()}

@callback load_since(session_id :: String.t(), after_turn :: integer(), opts :: keyword()) ::
  {:ok, [map()]} | {:error, term()}

@callback list_sessions(workspace :: String.t(), opts :: keyword()) ::
  {:ok, [session_summary()]} | {:error, term()}
```

Event format (one JSON object per line):
```json
{"type":"llm_response","turn":3,"data":{...},"timestamp":"2026-04-06T12:00:00Z"}
{"type":"tool_call","turn":3,"data":{"name":"read_file","input":{...}},"timestamp":"..."}
{"type":"tool_result","turn":3,"data":{"name":"read_file","output":"..."},"timestamp":"..."}
{"type":"phase_transition","turn":3,"data":{"from":"plan","to":"execute"},"timestamp":"..."}
```

Session resumption: `Agentic.resume/1` loads the transcript, reconstructs the compact conversation, and starts the pipeline with `ctx.turns_used` set to the transcript length. Plan state is serialized into the transcript so it survives resumption.

**Files:**
- `lib/agentic/persistence/transcript.ex` — behaviour definition
- `lib/agentic/persistence/transcript/local.ex` — JSONL file backend

---

### 4.3 `Agentic.Persistence.Plan`

**Addresses:** PlanBuilder (§5.2), PlanTracker (§5.3), Plan Structure (§8)

CRUD for structured plans with step-level status tracking. The `:local` implementation stores JSON files at `<workspace>/.agentic/plans/<plan_id>.json`.

```elixir
@callback create(plan :: plan_struct(), opts :: keyword()) ::
  {:ok, plan_struct()} | {:error, term()}

@callback get(plan_id :: String.t(), opts :: keyword()) ::
  {:ok, plan_struct()} | {:error, :not_found}

@callback update_step(plan_id :: String.t(), step_index :: integer(), updates :: map(), opts :: keyword()) ::
  {:ok, plan_struct()} | {:error, term()}

@callback list_plans(workspace :: String.t(), opts :: keyword()) ::
  {:ok, [plan_summary()]} | {:error, term()}
```

**Files:**
- `lib/agentic/persistence/plan.ex` — behaviour definition
- `lib/agentic/persistence/plan/local.ex` — JSON file backend

---

### 4.4 `Agentic.Persistence.Knowledge`

**Addresses:** ContextKeeper durable persistence, working memory fact storage

**Recollect is the preferred knowledge store.** It is already a declared dependency of Agentic (`mix.exs` line 31) and lives at `../recollect`. Recollect provides:

- Tier 2 API: `remember/2`, `forget/1`, `connect/4`, `search/2` — maps almost directly onto this behaviour
- Hybrid vector + graph search with configurable hops
- Auto-embedding via configurable providers
- Entity/relation extraction with LLM assistance
- Memory decay for stale entries
- Fact supersession via confidence demotion

The `:recollect` backend delegates to Recollect directly. The `:local` fallback uses file-based storage for lightweight/no-DB scenarios.

```elixir
@callback search(query :: String.t(), opts :: keyword()) ::
  {:ok, [entry()]} | {:error, term()}

@callback create_entry(entry :: entry(), opts :: keyword()) ::
  {:ok, entry()} | {:error, term()}

@callback get_entry(entry_id :: String.t(), opts :: keyword()) ::
  {:ok, entry()} | {:error, :not_found}

@callback get_edges(entry_id :: String.t(), direction :: :from | :to, opts :: keyword()) ::
  {:ok, [edge()]} | {:error, term()}

@callback create_edge(from_id :: String.t(), to_id :: String.t(), relation :: String.t(), opts :: keyword()) ::
  {:ok, edge()} | {:error, term()}

@callback recent(scope_id :: String.t(), opts :: keyword()) ::
  {:ok, [entry()]} | {:error, term()}

@callback supersede(scope_id :: String.t(), entity :: String.t(), relation :: String.t(), new_value :: String.t()) ::
  {:ok, [entry()]} | {:error, term()}
```

Types:
```elixir
@type entry :: %{
  id: String.t(),
  content: String.t(),
  entry_type: String.t(),
  source: String.t(),
  scope_id: String.t() | nil,
  owner_id: String.t() | nil,
  metadata: map(),
  confidence: float(),
  inserted_at: DateTime.t()
}

@type edge :: %{
  id: String.t(),
  source_entry_id: String.t(),
  target_entry_id: String.t(),
  relation: String.t(),
  weight: float()
}
```

Behaviour-to-Recollect API mapping:

| Behaviour callback | Recollect equivalent |
|---|---|
| `create_entry/2` | `Recollect.remember/2` |
| `search/2` | `Recollect.search/2` (hybrid vector + graph) |
| `get_entry/2` | `Recollect.Knowledge.recent/2` (by scope) |
| `get_edges/3` | `Recollect.GraphStore.impl().get_relations/2` |
| `create_edge/4` | `Recollect.connect/4` |
| `recent/2` | `Recollect.Knowledge.recent/2` |
| `supersede/4` | `Recollect.Knowledge.supersede/4` |

The `:recollect` backend ships as `lib/agentic/persistence/knowledge/recollect.ex`:

```elixir
defmodule Agentic.Persistence.Knowledge.Recollect do
  @behaviour Agentic.Persistence.Knowledge

  @impl true
  def search(query, opts), do: Recollect.search(query, opts)

  @impl true
  def create_entry(entry, opts) do
    Recollect.remember(entry.content, opts)
  end

  @impl true
  def recent(scope_id, opts), do: Recollect.Knowledge.recent(scope_id, opts)

  @impl true
  def create_edge(from_id, to_id, relation, opts) do
    Recollect.connect(from_id, to_id, relation, opts)
  end

  @impl true
  def get_edges(entry_id, _direction, opts) do
    owner_id = Keyword.get(opts, :owner_id)
    Recollect.GraphStore.impl().get_relations(owner_id, entry_id)
  end

  @impl true
  def get_entry(entry_id, opts) do
    scope_id = Keyword.get(opts, :scope_id)
    case Recollect.Knowledge.recent(scope_id, limit: 100) do
      {:ok, entries} ->
        case Enum.find(entries, &(&1.id == entry_id)) do
          nil -> {:error, :not_found}
          entry -> {:ok, entry}
        end
      error -> error
    end
  end

  @impl true
  def supersede(scope_id, entity, relation, new_value) do
    Recollect.Knowledge.supersede(scope_id, entity, relation, new_value)
  end
end
```

The `:local` fallback ships as `lib/agentic/persistence/knowledge/local.ex` using a JSONL index file at `<workspace>/.agentic/knowledge.jsonl`.

**Host integration:** Homunculus already has `RecollectBridge` that calls into Recollect. SCE would need a similar adapter. Both projects provide the Recollect repo config, and the `:recollect` backend works without additional setup.

---

## 5. Backend Resolution

Extend the existing `Storage.Context` resolution to cover all four behaviours:

```elixir
# In config or at runtime:
Agentic.configure(
  storage: %{
    backend: Agentic.Storage.Local,
    config: %{root: "/path/to/workspace"}
  },
  persistence: %{
    transcript: {Agentic.Persistence.Transcript.Local, %{}},
    plan: {Agentic.Persistence.Plan.Local, %{}},
    knowledge: {Agentic.Persistence.Knowledge.Recollect, %{}}
  }
)
```

Default when no persistence is configured: everything stays filesystem-backed as today. Zero deps, zero config, zero changes for existing users.

---

## 6. Host Application Integration Guide

For a host application already using Ash (like homunculus or SCE), the integration path is:

1. **Define Ash resources** matching the behaviour's data types (e.g., `SessionEvent`, `Plan`, `PlanStep`, `KnowledgeEntry`, `KnowledgeEdge`)
2. **Implement the behaviour module** with Ash-backed CRUD:

```elixir
defmodule MyApp.Agentic.AshTranscript do
  @behaviour Agentic.Persistence.Transcript

  @impl true
  def append(session_id, event, _opts) do
    SessionEvent
    |> Ash.Changeset.for_create(:create, %{
      session_id: session_id,
      type: event.type,
      turn: event.turn,
      data: event.data,
      timestamp: event.timestamp
    }, authorize?: false)
    |> Ash.create()
  end
end
```

3. **Wire in config** when calling `Agentic.run/1`

This mirrors how `homunculus_agent`'s `AgenticCallbacks` bridges to Ash today — the agent runtime stays clean, the host provides the implementation.

---

## 7. Dependency Changes

| Package | Current | Proposed | Reason |
|---|---|---|---|
| `ecto_sql` | Declared, unused | **Keep** | Required by recollect |
| `postgrex` | Declared, unused | **Keep** | Required by recollect |
| `recollect` | Declared (GitHub) | **Keep** | Preferred knowledge store |
| `ash` | Not present | **Not added** | Agentic stays decoupled |
| `jason` | Required | **Keep** | JSONL serialization |
