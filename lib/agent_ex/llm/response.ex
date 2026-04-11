defmodule AgentEx.LLM.Response do
  @moduledoc """
  Normalized chat response shape produced by every transport.

  ## Fields

    * `:content` — list of content blocks. Each block is a map of one of:
        - `%{type: :text, text: String.t()}`
        - `%{type: :tool_use, id: String.t(), name: String.t(), input: map()}`
    * `:stop_reason` — one of `:end_turn | :tool_use | :max_tokens | :error`
    * `:usage` — `%{input_tokens, output_tokens, cache_read, cache_write}`
      (cache fields default to `0`)
    * `:cost` — computed USD cost for this call (set by LLMCall stage)
    * `:model_id` — provider-local model id (when known)
    * `:raw` — the unmodified decoded response body, kept for debugging

  Transports translate their wire format into this shape. The host
  application and all loop stages consume this struct directly.
  """

  @type content_block ::
          %{type: :text, text: String.t()}
          | %{type: :tool_use, id: String.t(), name: String.t(), input: map()}

  @type stop_reason :: :end_turn | :tool_use | :max_tokens | :error

  @type usage :: %{
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer(),
          cache_read: non_neg_integer(),
          cache_write: non_neg_integer()
        }

  @type t :: %__MODULE__{
          content: [content_block()],
          stop_reason: stop_reason(),
          usage: usage(),
          cost: float(),
          model_id: String.t() | nil,
          raw: term()
        }

  @behaviour Access

  defstruct content: [],
            stop_reason: :end_turn,
            usage: %{input_tokens: 0, output_tokens: 0, cache_read: 0, cache_write: 0},
            cost: nil,
            model_id: nil,
            raw: nil

  @impl Access
  def fetch(response, key) when is_atom(key), do: Map.fetch(response, key)

  def fetch(response, key) when is_binary(key) do
    atom_key = String.to_existing_atom(key)
    Map.fetch(response, atom_key)
  rescue
    ArgumentError -> :error
  end

  @impl Access
  def get_and_update(response, key, fun) when is_atom(key) do
    Map.get_and_update(response, key, fun)
  end

  @impl Access
  def pop(response, key) when is_atom(key) do
    Map.pop(response, key)
  end
end
