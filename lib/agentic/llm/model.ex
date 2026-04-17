defmodule Agentic.LLM.Model do
  @moduledoc """
  Shared struct describing a single LLM model.

  Providers populate `default_models/0` with these. The `Agentic.LLM.Catalog`
  GenServer merges static, discovered, and user-overridden model lists.

  Fields:

    * `:id` — provider-local model id (e.g. `"claude-opus-4-20250514"`).
    * `:provider` — atom id of the provider module (e.g. `:anthropic`).
    * `:label` — human-readable label for UI.
    * `:context_window` — input token budget.
    * `:max_output_tokens` — generation budget.
    * `:cost` — map `%{input: ..., output: ..., cache_read: ..., cache_write: ...}`
      with prices in USD per 1M tokens.
    * `:capabilities` — `MapSet` of capability tags
      (`:chat`, `:tools`, `:vision`, `:embeddings`, `:reasoning`,
      `:prompt_caching`, `:json_mode`, `:free`, …).
    * `:tier_hint` — provider-suggested tier (`:primary`, `:lightweight`,
      or `nil`).
    * `:source` — where the entry came from (`:static`, `:discovered`,
      `:user_config`).
  """

  @type capability :: atom()

  @type cost :: %{
          required(:input) => float(),
          required(:output) => float(),
          optional(:cache_read) => float(),
          optional(:cache_write) => float()
        }

  @type t :: %__MODULE__{
          id: String.t(),
          provider: atom(),
          label: String.t() | nil,
          context_window: pos_integer() | nil,
          max_output_tokens: pos_integer() | nil,
          cost: cost() | nil,
          capabilities: MapSet.t(),
          tier_hint: :primary | :lightweight | nil,
          source: :static | :discovered | :user_config
        }

  defstruct id: nil,
            provider: nil,
            label: nil,
            context_window: nil,
            max_output_tokens: nil,
            cost: nil,
            capabilities: %MapSet{},
            tier_hint: nil,
            source: :static
end
