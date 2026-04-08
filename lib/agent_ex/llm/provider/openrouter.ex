defmodule AgentEx.LLM.Provider.OpenRouter do
  @moduledoc """
  OpenRouter provider.

  Uses `AgentEx.LLM.Transport.OpenAIChatCompletions` transport with
  OpenRouter-specific base URL and analytics headers. Supports
  dynamic catalog fetching from `/api/v1/models`.
  """

  @behaviour AgentEx.LLM.Provider

  alias AgentEx.LLM.{Credentials, Model}

  @default_base_url "https://openrouter.ai/api/v1"

  @impl true
  def id, do: :openrouter

  @impl true
  def label, do: "OpenRouter"

  @impl true
  def transport, do: AgentEx.LLM.Transport.OpenAIChatCompletions

  @impl true
  def default_base_url, do: @default_base_url

  @impl true
  def env_vars, do: ["OPENROUTER_API_KEY"]

  @impl true
  def supports, do: MapSet.new([:chat, :tools, :vision, :embeddings])

  @impl true
  def request_headers(%Credentials{} = _creds) do
    [
      {"HTTP-Referer", "https://github.com/lenzg/worth"},
      {"X-Title", "worth"}
    ]
  end

  @impl true
  def default_models do
    [
      %Model{
        id: "anthropic/claude-sonnet-4",
        provider: :openrouter,
        label: "Claude Sonnet 4 (via OpenRouter)",
        context_window: 200_000,
        max_output_tokens: 16_384,
        cost: %{input: 3.0, output: 15.0},
        capabilities: MapSet.new([:chat, :tools, :vision]),
        tier_hint: :primary,
        source: :static
      }
    ]
  end

  @impl true
  def fetch_catalog(%Credentials{api_key: api_key} = _creds) when is_binary(api_key) and api_key != "" do
    url = "#{@default_base_url}/models"

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"content-type", "application/json"}
    ]

    case Req.get(url, headers: headers, receive_timeout: 15_000) do
      {:ok, %{status: 200, body: %{"data" => models}}} ->
        parsed =
          models
          |> Enum.map(&parse_model/1)
          |> Enum.filter(&(&1 != nil))

        {:ok, parsed}

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  def fetch_catalog(_), do: :not_supported

  @impl true
  def fetch_usage(%Credentials{api_key: api_key} = _creds) when is_binary(api_key) and api_key != "" do
    url = "#{@default_base_url}/auth/key"

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"content-type", "application/json"}
    ]

    case Req.get(url, headers: headers, receive_timeout: 10_000) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      _ ->
        :not_supported
    end
  rescue
    _ -> :not_supported
  end

  def fetch_usage(_), do: :not_supported

  @impl true
  def classify_http_error(_status, _body, _headers), do: :default

  defp parse_model(raw) do
    id = raw["id"]
    context = raw["context_length"]
    pricing = raw["pricing"] || %{}
    params = raw["supported_parameters"] || []
    output = get_in(raw, ["architecture", "output_modalities"]) || []

    prompt_price = parse_price(pricing["prompt"])
    completion_price = parse_price(pricing["completion"])

    capabilities = MapSet.new()

    capabilities =
      if "tools" in params,
        do: MapSet.put(capabilities, :tools),
        else: capabilities

    capabilities =
      if "text" in output,
        do: MapSet.put(capabilities, :chat),
        else: capabilities

    capabilities =
      if "embeddings" in (raw["output_modalities"] || output),
        do: MapSet.put(capabilities, :embeddings),
        else: capabilities

    capabilities =
      if "reasoning" in params,
        do: MapSet.put(capabilities, :reasoning),
        else: capabilities

    capabilities =
      if prompt_price == 0.0 and completion_price == 0.0,
        do: MapSet.put(capabilities, :free),
        else: capabilities

    tier_hint =
      cond do
        context >= 64_000 -> :primary
        context >= 8_000 -> :lightweight
        true -> nil
      end

    %Model{
      id: id,
      provider: :openrouter,
      label: raw["name"] || id,
      context_window: context,
      max_output_tokens: get_in(raw, ["top_provider", "max_completion_tokens"]),
      cost: %{input: prompt_price, output: completion_price},
      capabilities: capabilities,
      tier_hint: tier_hint,
      source: :discovered
    }
  end

  defp parse_price(str) when is_binary(str) do
    case Float.parse(str) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp parse_price(_), do: 0.0
end
