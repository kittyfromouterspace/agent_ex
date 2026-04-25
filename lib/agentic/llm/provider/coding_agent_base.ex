defmodule Agentic.LLM.Provider.CodingAgentBase do
  @moduledoc """
  Macro that synthesizes a catalog-only `Agentic.LLM.Provider`
  implementation for an ACP-compatible coding-agent CLI (Cursor,
  Gemini CLI, Goose, GitHub Copilot, Kimi, Qwen, …).

  These agents all route to one or more of the big frontier model
  families internally — most expose Anthropic Claude, OpenAI GPT,
  and Google Gemini. We surface them in the Catalog as alternative
  pathways for those same canonical model families so the
  multi-pathway router can score them alongside Anthropic-direct,
  OpenRouter, etc.

  ## Usage

      defmodule Agentic.LLM.Provider.Cursor do
        use Agentic.LLM.Provider.CodingAgentBase,
          id: :cursor,
          cli_name: "cursor-agent",
          label: "Cursor",
          # Optional — defaults to the frontier coding set below.
          # Each tuple is {provider_local_id, label, tier, ctx_window}
          model_overrides: [...]
      end

  ## Why a macro

  Per-agent modules get a single place each (~5 lines) and the
  shared catalog/availability machinery lives here. Adding a new
  detected agent is a trivial PR. The model list defaults are
  intentionally a small "frontier coding" set — agents that route
  exclusively to one family override `model_overrides`.
  """

  @doc """
  Default model seeds used by every ACP coding agent that doesn't
  override them. Mirrors what `Agentic.LLM.Provider.OpenCode`
  declared — the canonical_id mapping in `Canonical` then groups
  these with their HTTP siblings.
  """
  def default_seeds do
    [
      {"anthropic/claude-sonnet-4", "Claude Sonnet 4", :primary, 200_000},
      {"anthropic/claude-opus-4", "Claude Opus 4", :primary, 200_000},
      {"openai/gpt-5.5", "GPT-5.5", :primary, 200_000},
      {"google/gemini-3-pro", "Gemini 3 Pro", :primary, 1_000_000}
    ]
  end

  defmacro __using__(opts) do
    id = Keyword.fetch!(opts, :id)
    cli_name = Keyword.fetch!(opts, :cli_name)
    label = Keyword.fetch!(opts, :label)
    overrides = Keyword.get(opts, :model_overrides)

    # Compute the default-models AST. If the caller gave overrides we
    # inline them into a runtime call to `build_models/3`; otherwise
    # we delegate to `default_seeds/0` at runtime. Both branches go
    # through the same builder helper so there's exactly one shape
    # for Dialyzer to analyze. We avoid `Macro.escape` because Elixir
    # AST cannot represent >2-tuples as literals — escaping a list of
    # 4-tuples produces `{:{}, meta, [...]}` AST nodes that fail to
    # match the function head at runtime.
    default_models_body =
      if overrides do
        quote do
          Agentic.LLM.Provider.CodingAgentBase.build_models(
            unquote(id),
            unquote(label),
            unquote(overrides)
          )
        end
      else
        quote do
          Agentic.LLM.Provider.CodingAgentBase.build_models(
            unquote(id),
            unquote(label),
            Agentic.LLM.Provider.CodingAgentBase.default_seeds()
          )
        end
      end

    quote do
      @behaviour Agentic.LLM.Provider

      alias Agentic.LLM.Credentials

      @cli_name unquote(cli_name)

      @impl true
      def id, do: unquote(id)

      @impl true
      def label, do: unquote(label) <> " (CLI)"

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
        unquote(default_models_body)
      end

      @impl true
      def fetch_catalog(_creds), do: :not_supported

      @impl true
      def fetch_usage(_creds), do: :not_supported

      @impl true
      def classify_http_error(_status, _body, _headers), do: :default

      @doc "Three-state availability for the #{unquote(label)} CLI pathway."
      @spec availability(any()) :: :ready | :unavailable
      def availability(_account \\ nil) do
        if System.find_executable(@cli_name), do: :ready, else: :unavailable
      end
    end
  end

  @doc """
  Builds a `[Model.t()]` from a seed list. Called by the generated
  `default_models/0` in each per-agent wrapper. Public so the macro
  can emit a call to it without escaping the seed list (which would
  mangle 4-tuples through the AST representation).
  """
  @spec build_models(atom(), String.t(), [{String.t(), String.t(), atom(), integer()}]) ::
          [Agentic.LLM.Model.t()]
  def build_models(provider_id, agent_label, seeds) do
    Enum.map(seeds, fn {model_id, model_label, tier, ctx} ->
      %Agentic.LLM.Model{
        id: model_id,
        provider: provider_id,
        label: "#{model_label} (via #{agent_label})",
        context_window: ctx,
        max_output_tokens: 8_192,
        cost: %{input: 0.0, output: 0.0},
        capabilities: MapSet.new([:chat, :tools]),
        tier_hint: tier,
        source: :static
      }
    end)
  end
end
