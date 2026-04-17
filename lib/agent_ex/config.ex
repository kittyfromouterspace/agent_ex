defmodule AgentEx.Config do
  @moduledoc """
  Runtime config surface for `agent_ex`, loaded from
  `Application.get_all_env(:agent_ex)`.

  Hosts (worth, future projects) configure agent_ex through the
  standard Elixir config flow:

      config :agent_ex,
        providers: [AgentEx.LLM.Provider.Anthropic, ...],
        catalog: [persist_path: "~/.worth/catalog.json", ...]

  This module exposes typed accessors validated via `nimble_options`.
  """

  @providers_schema [
    providers: [
      type: {:list, :atom},
      default: [],
      doc: "List of provider modules to register at boot"
    ],
    catalog: [
      type: :keyword_list,
      default: [],
      doc: "Catalog GenServer options"
    ],
    usage: [
      type: :keyword_list,
      default: [],
      doc: "UsageManager options"
    ],
    router: [
      type: :keyword_list,
      default: [],
      doc: "ModelRouter options"
    ],
    telemetry: [
      type: :keyword_list,
      default: [enabled: true],
      doc: "Telemetry options"
    ]
  ]

  @doc "All providers configured at compile time."
  @spec providers() :: [module()]
  def providers do
    get_env(:providers, [])
  end

  @doc "Catalog config key."
  @spec catalog(key :: atom(), default :: term()) :: term()
  def catalog(key, default \\ nil) do
    get_in_env(:catalog, key, default)
  end

  @doc "Usage config key."
  @spec usage(key :: atom(), default :: term()) :: term()
  def usage(key, default \\ nil) do
    get_in_env(:usage, key, default)
  end

  @doc "Router config key."
  @spec router(key :: atom(), default :: term()) :: term()
  def router(key, default \\ nil) do
    get_in_env(:router, key, default)
  end

  @doc "Telemetry config key."
  @spec telemetry(key :: atom(), default :: term()) :: term()
  def telemetry(key, default \\ nil) do
    get_in_env(:telemetry, key, default)
  end

  @doc """
  Returns the preferred embedding model id, or nil if not configured.
  Hosts can set `config :agent_ex, embedding_model: "text-embedding-3-small"`.
  """
  @spec embedding_model() :: String.t() | nil
  def embedding_model do
    get_env(:embedding_model, nil)
  end

  @doc "Validate and return the full config map."
  @spec validate!() :: keyword()
  def validate! do
    env = Application.get_all_env(:agent_ex)

    NimbleOptions.validate!(
      Keyword.take(env, Keyword.keys(@providers_schema)),
      @providers_schema
    )
  end

  defp get_env(key, default) do
    Application.get_env(:agent_ex, key, default)
  end

  defp get_in_env(top, key, default) do
    top
    |> get_env([])
    |> Keyword.get(key, default)
  end
end
