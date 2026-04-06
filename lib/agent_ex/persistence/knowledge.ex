defmodule AgentEx.Persistence.Knowledge do
  @moduledoc """
  Behaviour for knowledge storage — entries, edges, search, and supersession.

  The `:local` fallback uses file-based storage at
  `<workspace>/.agent_ex/knowledge.jsonl`.

  The `:mneme` backend delegates to the Mneme knowledge graph.
  """

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

  @callback search(query :: String.t(), opts :: keyword()) ::
              {:ok, [entry()]} | {:error, term()}

  @callback create_entry(entry :: entry(), opts :: keyword()) ::
              {:ok, entry()} | {:error, term()}

  @callback get_entry(entry_id :: String.t(), opts :: keyword()) ::
              {:ok, entry()} | {:error, :not_found}

  @callback get_edges(entry_id :: String.t(), direction :: :from | :to, opts :: keyword()) ::
              {:ok, [edge()]} | {:error, term()}

  @callback create_edge(
              from_id :: String.t(),
              to_id :: String.t(),
              relation :: String.t(),
              opts :: keyword()
            ) ::
              {:ok, edge()} | {:error, term()}

  @callback recent(scope_id :: String.t(), opts :: keyword()) ::
              {:ok, [entry()]} | {:error, term()}

  @callback supersede(
              scope_id :: String.t(),
              entity :: String.t(),
              relation :: String.t(),
              new_value :: String.t()
            ) ::
              {:ok, [entry()]} | {:error, term()}
end
