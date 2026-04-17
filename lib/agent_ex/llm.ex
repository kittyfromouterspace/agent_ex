defmodule AgentEx.LLM do
  @moduledoc """
  Top-level entry point for chat and embedding calls.

  Wraps `AgentEx.LLM.Provider` with two conveniences:

    * `chat/2` and `chat_tier/3` for chat completions
    * `embed/2` and `embed_tier/3` for vector embeddings

  Both flavours route through the configured provider stack and
  return canonical `%Response{}` / `{:ok, vectors, model_id}` shapes.

  ## Embed return shape

  `embed/2` and `embed_tier/3` always return a list of vectors,
  even when called with a single string input. The third tuple
  element is the model id used to produce the vectors so callers
  (e.g. mneme's reembed pipeline) can store provenance.

      {:ok, [vector, ...], "text-embedding-3-small"} | {:error, %Error{}}
  """

  alias AgentEx.LLM.Catalog
  alias AgentEx.LLM.Credentials
  alias AgentEx.LLM.Error
  alias AgentEx.LLM.Provider
  alias AgentEx.LLM.ProviderRegistry
  alias AgentEx.ModelRouter

  require Logger

  @type embed_result :: {:ok, [[float()]], String.t()} | {:error, Error.t()}

  @doc "Chat completion via a provider module + canonical params."
  def chat(params, opts \\ []) do
    provider =
      case Keyword.get(opts, :provider) do
        nil -> raise ArgumentError, "AgentEx.LLM.chat/2 requires :provider option"
        atom when is_atom(atom) -> ProviderRegistry.get(atom) || atom
      end

    Provider.chat(provider, params, opts)
  end

  @doc """
  Chat completion via tier resolution with full failover.

  Resolves every healthy route in `tier` from the ModelRouter and walks
  them in priority order with error classification and health reporting.
  Accepts an optional `llm_chat` callback (same shape as the loop callback)
  for callers that want to customise dispatch (e.g. host app credential
  injection). Falls back to direct provider dispatch when no callback is
  provided. Returns `{:ok, %Response{}}` or `{:error, %Error{}}`.

  ## Options

    * `:llm_chat` — `(map() -> {:ok, response} | {:error, term()})` callback.
      When provided, each route is injected as `params["_route"]` and the
      callback is invoked. Otherwise direct `Provider.chat/3` is used.
  """
  def chat_tier(params, tier, opts \\ []) do
    llm_chat = Keyword.get(opts, :llm_chat)

    case resolve_routes(tier) do
      {:ok, [_ | _] = routes} ->
        walk_routes(routes, params, tier, llm_chat, opts, nil)

      _ ->
        {:error, %Error{message: "no provider available for tier #{tier}", classification: :permanent}}
    end
  end

  defp resolve_routes(tier) do
    ModelRouter.resolve_all(tier)
  catch
    :exit, {:noproc, _} -> {:error, :router_unavailable}
    :exit, _ -> {:error, :router_unavailable}
  end

  defp walk_routes([], _params, tier, _llm_chat, _opts, last_error) do
    Logger.debug("AgentEx.LLM.chat_tier: all routes for tier #{tier} exhausted")

    {:error,
     last_error ||
       %Error{message: "all routes exhausted for tier #{tier}", classification: :permanent}}
  end

  defp walk_routes([route | rest], params, tier, llm_chat, opts, _last) do
    Logger.debug("AgentEx.LLM.chat_tier: trying #{route.provider_name}/#{route.model_id} (tier #{tier})")

    result =
      if llm_chat do
        params_with_route = Map.put(params, "_route", route)
        llm_chat.(params_with_route)
      else
        direct_dispatch(params, route, opts)
      end

    case result do
      {:ok, _} = ok ->
        ModelRouter.report_success(route.provider_name, route.model_id)
        ok

      {:error, _reason} = err ->
        failure = classify_tier_error(err)
        retry_ms = extract_retry_after(err)

        Logger.warning(
          "AgentEx.LLM.chat_tier: #{route.provider_name}/#{route.model_id} failed (#{failure}); trying next"
        )

        report_opts = if is_integer(retry_ms), do: [retry_after_ms: retry_ms], else: []
        ModelRouter.report_error(route.provider_name, route.model_id, failure, report_opts)
        walk_routes(rest, params, tier, llm_chat, opts, err)
    end
  end

  defp direct_dispatch(params, route, opts) do
    provider_name = route.provider_name
    model_id = route.model_id

    case ProviderRegistry.get(provider_name) do
      nil ->
        {:error,
         %Error{
           message: "unknown provider #{provider_name}",
           classification: :permanent
         }}

      provider ->
        Provider.chat(provider, params, Keyword.put(opts, :model, model_id))
    end
  end

  defp classify_tier_error({:error, %{classification: c}}), do: legacy_failure(c)
  defp classify_tier_error({:error, %{status: 429}}), do: :rate_limit
  defp classify_tier_error({:error, %{status: s}}) when s in [401, 403], do: :auth_error
  defp classify_tier_error({:error, %{status: s}}) when is_integer(s) and s >= 500, do: :other

  defp classify_tier_error({:error, %{message: msg}}) when is_binary(msg), do: classify_tier_error({:error, msg})

  defp classify_tier_error({:error, reason}) when is_binary(reason) do
    cond do
      String.contains?(reason, "429") or String.contains?(reason, "rate") -> :rate_limit
      String.contains?(reason, "401") or String.contains?(reason, "403") -> :auth_error
      String.contains?(reason, "timeout") or String.contains?(reason, "connection") -> :connection_error
      true -> :other
    end
  end

  defp classify_tier_error(_), do: :other

  defp legacy_failure(:rate_limit), do: :rate_limit
  defp legacy_failure(:overloaded), do: :rate_limit
  defp legacy_failure(:auth), do: :auth_error
  defp legacy_failure(:auth_permanent), do: :auth_error
  defp legacy_failure(:billing), do: :auth_error
  defp legacy_failure(:timeout), do: :connection_error
  defp legacy_failure(:transient), do: :connection_error
  defp legacy_failure(:permanent), do: :other
  defp legacy_failure(:format), do: :other
  defp legacy_failure(:model_not_found), do: :other
  defp legacy_failure(:context_overflow), do: :other
  defp legacy_failure(:session_expired), do: :auth_error
  defp legacy_failure(_), do: :other

  defp extract_retry_after({:error, %{retry_after_ms: ms}}) when is_integer(ms) and ms > 0, do: ms
  defp extract_retry_after(_), do: nil

  @doc """
  Generate embeddings for one or more strings via an explicit provider.

  Required opts:

    * `:provider` — provider id atom (e.g. `:openai`)
    * `:model`    — model id string (e.g. `"text-embedding-3-small"`)
  """
  @spec embed(String.t() | [String.t()], keyword()) :: embed_result()
  def embed(text_or_list, opts \\ []) do
    provider_id = Keyword.fetch!(opts, :provider)
    model_id = Keyword.fetch!(opts, :model)

    case lookup_provider(provider_id) do
      nil ->
        {:error, %Error{message: "unknown provider #{inspect(provider_id)}", classification: :permanent}}

      provider ->
        embed_via_provider(provider, model_id, text_or_list)
    end
  end

  @doc """
  Generate embeddings via tier-based model resolution.

  Tier resolution order:

    1. Explicit `opts[:model]` + `opts[:provider]` (skips Catalog)
    2. `Catalog.find(has: :embeddings, tier: tier)` → first match
    3. Fallback to first model with the `:embeddings` capability
  """
  @spec embed_tier(String.t() | [String.t()], atom(), keyword()) :: embed_result()
  def embed_tier(text_or_list, tier \\ :embeddings, opts \\ []) do
    case resolve_embedding_target(tier, opts) do
      {:ok, provider, model_id} ->
        embed_via_provider(provider, model_id, text_or_list)

      :none ->
        {:error,
         %Error{
           message: "no embedding model available for tier #{inspect(tier)}",
           classification: :permanent
         }}
    end
  end

  # ---- internals ----

  defp lookup_provider(provider_id) when is_atom(provider_id) do
    ProviderRegistry.get(provider_id)
  end

  defp lookup_provider(_), do: nil

  defp resolve_embedding_target(tier, opts) do
    explicit_model = Keyword.get(opts, :model)
    explicit_provider = Keyword.get(opts, :provider)

    if explicit_model && explicit_provider do
      case lookup_provider(explicit_provider) do
        nil -> :none
        mod -> {:ok, mod, explicit_model}
      end
    else
      candidates =
        case Catalog.find(tier: tier, has: :embeddings) do
          [] -> Catalog.find(has: :embeddings)
          list -> list
        end

      preferred_id = explicit_model || AgentEx.Config.embedding_model()

      candidates
      |> Enum.sort_by(&embedding_preference(&1, preferred_id))
      |> Enum.find_value(:none, fn model ->
        case lookup_provider(model.provider) do
          nil -> false
          mod -> {:ok, mod, model.id}
        end
      end)
    end
  end

  defp embedding_preference(model, preferred_id) do
    cond do
      is_binary(preferred_id) and model.id == preferred_id -> 0
      model.provider != :ollama -> 1
      true -> 2
    end
  end

  defp embed_via_provider(provider, model_id, text_or_list) do
    transport_mod = provider.transport()

    if function_exported?(transport_mod, :build_embedding_request, 2) do
      case Credentials.resolve(provider) do
        {:ok, creds} ->
          base_url = creds.base_url_override || provider.default_base_url()

          opts = [
            base_url: base_url,
            api_key: creds.api_key,
            model: model_id,
            extra_headers: creds.headers
          ]

          case transport_mod.build_embedding_request(text_or_list, opts) do
            :not_supported ->
              {:error,
               %Error{
                 message: "transport #{inspect(transport_mod)} does not support embeddings",
                 classification: :permanent
               }}

            request ->
              execute_embed(request, transport_mod, model_id)
          end

        :not_configured ->
          {:error,
           %Error{
             message: "#{provider.id()} not configured (set #{Enum.join(provider.env_vars(), " or ")})",
             classification: :auth
           }}
      end
    else
      {:error,
       %Error{
         message: "transport #{inspect(transport_mod)} does not implement embedding callbacks",
         classification: :permanent
       }}
    end
  end

  defp execute_embed(request, transport_mod, model_id) do
    start_time = System.monotonic_time()

    result =
      case Req.post(request.url,
             json: request.body,
             headers: request.headers,
             receive_timeout: 60_000
           ) do
        {:ok, %{status: status, body: body, headers: headers}} ->
          case transport_mod.parse_embedding_response(status, body, headers) do
            {:ok, vectors} -> {:ok, vectors, model_id}
            {:error, _} = err -> err
          end

        {:error, exception} ->
          {:error,
           %Error{
             message: "HTTP error: #{Exception.message(exception)}",
             classification: :timeout,
             raw: exception
           }}
      end

    duration = System.monotonic_time() - start_time
    emit_embed_telemetry(result, model_id, duration, request)
    result
  end

  defp emit_embed_telemetry(result, model_id, duration, request) do
    {input_count, status} =
      case result do
        {:ok, vectors, _} -> {length(vectors), :ok}
        {:error, _} -> {input_size(request), :error}
      end

    AgentEx.Telemetry.event(
      [:llm, :embed, :stop],
      %{
        duration: duration,
        input_count: input_count,
        cost_usd: 0.0
      },
      %{model: model_id, status: status}
    )
  end

  defp input_size(%{body: %{input: input}}) when is_list(input), do: length(input)
  defp input_size(%{body: %{input: input}}) when is_binary(input), do: 1
  defp input_size(_), do: 0
end
