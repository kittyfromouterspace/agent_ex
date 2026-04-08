defmodule AgentEx.LLM.Provider.Anthropic do
  @moduledoc """
  Anthropic Messages API provider.

  Uses `AgentEx.LLM.Transport.AnthropicMessages` transport.
  Static catalog — Anthropic does not expose a public model list
  endpoint without OAuth.
  """

  @behaviour AgentEx.LLM.Provider

  alias AgentEx.LLM.{Credentials, Model}

  @impl true
  def id, do: :anthropic

  @impl true
  def label, do: "Anthropic"

  @impl true
  def transport, do: AgentEx.LLM.Transport.AnthropicMessages

  @impl true
  def default_base_url, do: "https://api.anthropic.com/v1"

  @impl true
  def env_vars, do: ["ANTHROPIC_API_KEY"]

  @impl true
  def supports, do: MapSet.new([:chat, :tools, :vision, :prompt_caching])

  @impl true
  def request_headers(%Credentials{} = _creds), do: []

  @impl true
  def default_models do
    [
      %Model{
        id: "claude-sonnet-4-20250514",
        provider: :anthropic,
        label: "Claude Sonnet 4",
        context_window: 200_000,
        max_output_tokens: 16_384,
        cost: %{input: 3.0, output: 15.0, cache_read: 0.3, cache_write: 3.75},
        capabilities: MapSet.new([:chat, :tools, :vision, :prompt_caching]),
        tier_hint: :primary,
        source: :static
      },
      %Model{
        id: "claude-haiku-4-20250414",
        provider: :anthropic,
        label: "Claude Haiku 4",
        context_window: 200_000,
        max_output_tokens: 8_192,
        cost: %{input: 0.80, output: 4.0, cache_read: 0.08, cache_write: 1.0},
        capabilities: MapSet.new([:chat, :tools, :vision, :prompt_caching]),
        tier_hint: :lightweight,
        source: :static
      },
      %Model{
        id: "claude-opus-4-20250514",
        provider: :anthropic,
        label: "Claude Opus 4",
        context_window: 200_000,
        max_output_tokens: 16_384,
        cost: %{input: 15.0, output: 75.0, cache_read: 1.5, cache_write: 18.75},
        capabilities: MapSet.new([:chat, :tools, :vision, :prompt_caching]),
        tier_hint: :primary,
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
