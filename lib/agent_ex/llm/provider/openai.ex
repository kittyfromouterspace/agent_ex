defmodule AgentEx.LLM.Provider.OpenAI do
  @moduledoc """
  OpenAI Chat Completions provider.

  Uses `AgentEx.LLM.Transport.OpenAIChatCompletions` transport.
  Static catalog — the `/v1/models` endpoint requires auth and
  returns a very long list; curated defaults are more useful.
  """

  @behaviour AgentEx.LLM.Provider

  alias AgentEx.LLM.{Credentials, Model}

  @impl true
  def id, do: :openai

  @impl true
  def label, do: "OpenAI"

  @impl true
  def transport, do: AgentEx.LLM.Transport.OpenAIChatCompletions

  @impl true
  def default_base_url, do: "https://api.openai.com/v1"

  @impl true
  def env_vars, do: ["OPENAI_API_KEY"]

  @impl true
  def supports, do: MapSet.new([:chat, :tools, :vision, :embeddings, :json_mode])

  @impl true
  def request_headers(%Credentials{} = _creds), do: []

  @impl true
  def default_models do
    [
      %Model{
        id: "gpt-4o",
        provider: :openai,
        label: "GPT-4o",
        context_window: 128_000,
        max_output_tokens: 16_384,
        cost: %{input: 2.5, output: 10.0},
        capabilities: MapSet.new([:chat, :tools, :vision, :json_mode]),
        tier_hint: :primary,
        source: :static
      },
      %Model{
        id: "gpt-4o-mini",
        provider: :openai,
        label: "GPT-4o Mini",
        context_window: 128_000,
        max_output_tokens: 16_384,
        cost: %{input: 0.15, output: 0.6},
        capabilities: MapSet.new([:chat, :tools, :vision, :json_mode]),
        tier_hint: :lightweight,
        source: :static
      },
      %Model{
        id: "text-embedding-3-small",
        provider: :openai,
        label: "Text Embedding 3 Small",
        context_window: 8_191,
        max_output_tokens: nil,
        cost: %{input: 0.02},
        capabilities: MapSet.new([:embeddings]),
        tier_hint: nil,
        source: :static
      }
    ]
  end

  @impl true
  def fetch_catalog(_creds), do: :not_supported

  @impl true
  def fetch_usage(_creds), do: :not_supported

  @impl true
  def classify_http_error(_status, _body, _headers), do: :default
end
