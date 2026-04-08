defmodule AgentEx.LLM.Credentials do
  @moduledoc """
  Resolved credentials for a single provider.

  `resolve/1` walks the provider's declared `env_vars/0` in priority
  order and returns the first non-empty value wrapped in a `%Credentials{}`
  struct. The provider knows its own env var names; nothing else does.
  """

  @type t :: %__MODULE__{
          api_key: String.t() | nil,
          headers: [{String.t(), String.t()}],
          base_url_override: String.t() | nil,
          source: {:env, String.t()} | :none
        }

  defstruct api_key: nil,
            headers: [],
            base_url_override: nil,
            source: :none

  @doc """
  Resolve credentials for a provider module by walking its `env_vars/0`
  in priority order. Returns the first non-empty value.

      iex> Credentials.resolve(AgentEx.LLM.Provider.OpenAI)
      {:ok, %Credentials{api_key: "sk-...", source: {:env, "OPENAI_API_KEY"}}}

      iex> Credentials.resolve(AgentEx.LLM.Provider.Ollama)
      {:ok, %Credentials{api_key: nil, source: :none}}
  """
  @spec resolve(module()) :: {:ok, t()} | :not_configured
  def resolve(provider) when is_atom(provider) do
    env_vars = provider.env_vars()

    case find_first_env(env_vars) do
      {:ok, {var, key}} ->
        {:ok,
         %__MODULE__{
           api_key: key,
           headers: provider.request_headers(%__MODULE__{api_key: key}),
           source: {:env, var}
         }}

      :none ->
        if provider.id() == :ollama do
          {:ok,
           %__MODULE__{
             api_key: nil,
             headers: provider.request_headers(%__MODULE__{}),
             source: :none
           }}
        else
          :not_configured
        end
    end
  end

  @doc "Returns `true` when the provider has a usable credential."
  @spec available?(module()) :: boolean()
  def available?(provider) when is_atom(provider) do
    case resolve(provider) do
      {:ok, %__MODULE__{api_key: nil}} -> provider.id() == :ollama
      {:ok, %__MODULE__{}} -> true
      :not_configured -> false
    end
  end

  defp find_first_env([]), do: :none

  defp find_first_env([var | rest]) when is_binary(var) do
    case System.get_env(var) do
      nil -> find_first_env(rest)
      "" -> find_first_env(rest)
      key -> {:ok, {var, key}}
    end
  end
end
