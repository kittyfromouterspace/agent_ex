defmodule Agentic.LLM.Provider.Codex do
  @moduledoc """
  Catalog-only Provider wrapper for the OpenAI Codex CLI. See
  `Agentic.LLM.Provider.ClaudeCode` for the design rationale.

  Codex has no `--list-models` subcommand and uses bare model
  identifiers (no `provider/` prefix). The static seeds below mirror
  the `Agentic.LLM.Canonical` static-override table.
  """

  @behaviour Agentic.LLM.Provider

  alias Agentic.LLM.{Credentials, Model}

  @cli_name "codex"

  @impl true
  def id, do: :codex

  @impl true
  def label, do: "Codex (CLI)"

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
      {"gpt-5.5", "GPT-5.5 (via Codex)", :primary},
      {"gpt-5.4", "GPT-5.4 (via Codex)", :primary},
      {"gpt-5.4-mini", "GPT-5.4 Mini (via Codex)", :lightweight},
      {"gpt-5.3-codex", "GPT-5.3 Codex (via Codex)", :primary},
      {"gpt-5.2", "GPT-5.2 (via Codex)", :primary}
    ]

    Enum.map(seeds, fn {id, label, tier} ->
      %Model{
        id: id,
        provider: :codex,
        label: label,
        context_window: 200_000,
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
