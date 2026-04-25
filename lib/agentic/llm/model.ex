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
    * `:capabilities` — `MapSet` of capability tags. Tags describe what
      the model is genuinely good at; specialty models carry only their
      specialty tag so they are never selected for general chat by
      mistake. Recognised tags:

        * `:chat` — text-in/text-out conversational dialog. Implies the
          model is appropriate for plain conversation. Specialty
          models (image generation, audio output, embeddings) do not
          get `:chat`.
        * `:tools` — supports function calling. Only set on models
          that are also `:chat` capable.
        * `:vision` — accepts image input.
        * `:audio_in` — accepts audio input.
        * `:audio_out` — generates audio output (specialty).
        * `:image_gen` — generates image output (specialty).
        * `:embeddings` — generates embeddings (specialty).
        * `:reasoning` — supports extended thinking / reasoning.
        * `:prompt_caching` — supports prompt caching (Anthropic).
        * `:json_mode` — supports structured-output mode (OpenAI).
        * `:free` — zero per-token cost.
    * `:tier_hint` — provider-suggested tier (`:primary`, `:lightweight`,
      or `nil`).
    * `:source` — where the entry came from (`:static`, `:discovered`,
      `:user_config`).
    * `:endpoints` — list of provider endpoint maps from the OpenRouter
      `/endpoints` API (provider-specific pricing, uptime, latency,
      throughput). `nil` when not fetched.
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
          source: :static | :discovered | :user_config,
          endpoints: [map()] | nil
        }

  defstruct id: nil,
            provider: nil,
            label: nil,
            context_window: nil,
            max_output_tokens: nil,
            cost: nil,
            capabilities: %MapSet{},
            tier_hint: nil,
            source: :static,
            endpoints: nil
end
