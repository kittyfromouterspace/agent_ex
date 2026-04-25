defmodule Agentic.LLM.Provider.OpenCode do
  @moduledoc """
  Catalog-only Provider wrapper for the OpenCode CLI. See
  `Agentic.LLM.Provider.ClaudeCode` for the design rationale.

  OpenCode pulls its model list from `https://models.dev/api.json` —
  the same source `Agentic.LLM.Canonical` uses. We seed the catalog
  with a small static set covering the providers OpenCode is most
  often pointed at; users can extend via `default_models/0` overrides.
  """

  @behaviour Agentic.LLM.Provider

  alias Agentic.LLM.{Credentials, Model}

  @cli_name "opencode"

  @impl true
  def id, do: :opencode

  @impl true
  def label, do: "OpenCode (CLI)"

  @impl true
  def transport, do: Agentic.LLM.Transport.OpenAIChatCompletions

  @impl true
  def default_base_url, do: nil

  @impl true
  def env_vars, do: []

  @impl true
  def supports, do: MapSet.new([:chat, :tools])

  @impl true
  def request_headers(%Credentials{} = _creds), do: []

  @impl true
  def default_models do
    seeds = [
      {"anthropic/claude-sonnet-4", "Claude Sonnet 4 (via OpenCode)", :primary, 200_000},
      {"anthropic/claude-opus-4", "Claude Opus 4 (via OpenCode)", :primary, 200_000},
      {"openai/gpt-5.5", "GPT-5.5 (via OpenCode)", :primary, 200_000},
      {"z-ai/glm-4.7", "GLM-4.7 (via OpenCode)", :primary, 203_000}
    ]

    Enum.map(seeds, fn {id, label, tier, ctx} ->
      %Model{
        id: id,
        provider: :opencode,
        label: label,
        context_window: ctx,
        max_output_tokens: 8_192,
        cost: %{input: 0.0, output: 0.0},
        capabilities: MapSet.new([:chat, :tools]),
        tier_hint: tier,
        source: :static
      }
    end)
  end

  @impl true
  def fetch_catalog(_creds), do: :not_supported

  @impl true
  def fetch_usage(_creds), do: :not_supported

  @impl true
  def classify_http_error(_status, _body, _headers), do: :default

  @spec availability(any()) :: :ready | :unavailable
  def availability(_account \\ nil) do
    if System.find_executable(@cli_name), do: :ready, else: :unavailable
  end
end
