defmodule Agentic.Persistence.Transcript do
  @moduledoc """
  Behaviour for append-only session event logging.

  The `:local` implementation writes JSONL files to
  `<workspace>/.agentic/sessions/<session_id>.jsonl`.
  """

  @type session_summary :: %{
          session_id: String.t(),
          workspace: String.t(),
          event_count: non_neg_integer(),
          first_event_at: DateTime.t() | nil,
          last_event_at: DateTime.t() | nil
        }

  @callback append(session_id :: String.t(), event :: map(), opts :: keyword()) ::
              :ok | {:error, term()}

  @callback load(session_id :: String.t(), opts :: keyword()) ::
              {:ok, [map()]} | {:error, :not_found} | {:error, term()}

  @callback load_since(session_id :: String.t(), after_turn :: integer(), opts :: keyword()) ::
              {:ok, [map()]} | {:error, term()}

  @callback list_sessions(workspace :: String.t(), opts :: keyword()) ::
              {:ok, [session_summary()]} | {:error, term()}
end
