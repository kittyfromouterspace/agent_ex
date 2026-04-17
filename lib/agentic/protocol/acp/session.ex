defmodule Agentic.Protocol.ACP.Session do
  @moduledoc """
  ACP session lifecycle management.

  Manages the full ACP connection lifecycle:
  1. `initialize` -- negotiate protocol version and capabilities
  2. `authenticate` -- if agent requires authentication
  3. `session/new` -- create a new conversation session
  4. `session/prompt` -- send user messages, collect streaming updates
  5. `session/cancel` -- cancel an ongoing prompt turn
  6. Cleanup -- close connection gracefully

  ## Usage

      {:ok, session} = Agentic.Protocol.ACP.Session.connect(
        client: acp_client,
        workspace: "/path/to/project",
        permission_policy: :ask
      )

      {:ok, response, session} = Agentic.Protocol.ACP.Session.prompt(
        session,
        [%{"type" => "text", "text" => "Hello"}]
      )

      :ok = Agentic.Protocol.ACP.Session.cancel(session)
      :ok = Agentic.Protocol.ACP.Session.close(session)
  """

  require Logger

  alias Agentic.Protocol.ACP.Types

  @type session :: %__MODULE__{
          client: pid(),
          session_id: String.t() | nil,
          workspace: String.t(),
          agent_capabilities: map() | nil,
          agent_info: map() | nil,
          protocol_version: pos_integer() | nil,
          permission_policy: atom(),
          mcp_servers: [map()],
          updates: [map()],
          prompt_accumulator: String.t()
        }

  defstruct [
    :client,
    :session_id,
    :workspace,
    :agent_capabilities,
    :agent_info,
    :protocol_version,
    :permission_policy,
    :mcp_servers,
    updates: [],
    prompt_accumulator: ""
  ]

  @default_client_info %{
    "name" => "agentic",
    "title" => "Agentic",
    "version" => "0.2.0"
  }

  @default_client_capabilities %{
    "fs" => %{"readTextFile" => true, "writeTextFile" => true},
    "terminal" => true
  }

  # --- Connection ---

  @doc """
  Connect to an ACP agent: initialize, authenticate (if needed), create session.

  ## Options

    - `:client` - ACP Client pid (required)
    - `:workspace` - Working directory for the session (required)
    - `:permission_policy` - `:ask`, `:allow_all`, or `:deny_all` (default `:ask`)
    - `:mcp_servers` - List of MCP server configs to forward (default `[]`)
    - `:client_info` - Override client info sent during initialize
    - `:client_capabilities` - Override client capabilities
  """
  @spec connect(keyword()) :: {:ok, session()} | {:error, term()}
  def connect(opts) do
    client = Keyword.fetch!(opts, :client)
    workspace = Keyword.fetch!(opts, :workspace)
    permission_policy = Keyword.get(opts, :permission_policy, :ask)
    mcp_servers = Keyword.get(opts, :mcp_servers, [])
    client_info = Keyword.get(opts, :client_info, @default_client_info)
    client_capabilities = Keyword.get(opts, :client_capabilities, @default_client_capabilities)

    session = %__MODULE__{
      client: client,
      workspace: workspace,
      permission_policy: permission_policy,
      mcp_servers: mcp_servers
    }

    with :ok <- setup_notification_handler(session),
         {:ok, init_result} <- initialize(session, client_info, client_capabilities),
         session <- %{
           session
           | protocol_version: init_result["protocolVersion"],
             agent_capabilities: init_result["agentCapabilities"],
             agent_info: init_result["agentInfo"]
         },
         :ok <- maybe_authenticate(session, init_result["authMethods"]),
         {:ok, session_id} <- create_session(session) do
      {:ok, %{session | session_id: session_id}}
    end
  end

  # --- Prompt ---

  @doc """
  Send a prompt to the agent and collect the response.

  Returns `{:ok, response, session}` where response contains:
  - `:content` - accumulated text content
  - `:tool_calls` - list of tool calls made during the turn
  - `:stop_reason` - why the agent stopped
  - `:updates` - all raw session/update notifications received
  """
  @spec prompt(session(), [Types.content_block()], keyword()) ::
          {:ok, map(), session()} | {:error, term()}
  def prompt(%__MODULE__{session_id: nil} = _session, _content_blocks, _opts) do
    {:error, :no_session}
  end

  def prompt(%__MODULE__{} = session, content_blocks, opts) do
    timeout = Keyword.get(opts, :timeout, 120_000)

    params = %{
      "sessionId" => session.session_id,
      "prompt" => content_blocks
    }

    # Reset client-side accumulator before each prompt
    :ok = Agentic.Protocol.ACP.Client.reset_prompt_state(session.client)

    case Agentic.Protocol.ACP.Client.request(session.client, "session/prompt", params,
           timeout: timeout
         ) do
      {:ok, result} ->
        {accumulated_text, updates} =
          Agentic.Protocol.ACP.Client.get_prompt_state(session.client)

        # Some ACP agents return content directly in the response; prefer that
        # but fall back to accumulated streaming text. Content may be a string or
        # a list of content blocks.
        content =
          case result["content"] do
            nil ->
              accumulated_text

            text when is_binary(text) ->
              text

            [%{"type" => "text", "text" => text} | _] ->
              text

            blocks when is_list(blocks) ->
              Enum.map_join(blocks, "", &Types.content_block_to_text/1)

            other ->
              to_string(other)
          end

        Logger.debug(
          "ACP prompt result: content_length=#{String.length(content)}, accumulated_length=#{String.length(accumulated_text)}, result=#{inspect(result, limit: 200)}"
        )

        stop_reason =
          if is_map(result), do: result["stopReason"] || "end_turn", else: "end_turn"

        response = %{
          content: content,
          tool_calls: extract_tool_calls(updates),
          stop_reason: Types.parse_stop_reason(stop_reason),
          updates: updates,
          raw_result: result
        }

        {:ok, response, session}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # --- Cancel ---

  @doc "Cancel the current prompt turn."
  @spec cancel(session(), keyword()) :: :ok
  def cancel(%__MODULE__{session_id: nil} = _session, _opts), do: :ok

  def cancel(%__MODULE__{} = session, _opts) do
    params = %{"sessionId" => session.session_id}

    Agentic.Protocol.ACP.Client.notify(session.client, "session/cancel", params)
  end

  # --- Close ---

  @doc "Close the session and stop the client."
  @spec close(session(), keyword()) :: :ok
  def close(%__MODULE__{client: nil} = _session, _opts), do: :ok

  def close(%__MODULE__{} = session, _opts) do
    Agentic.Protocol.ACP.Client.stop(session.client)
  end

  # --- Session loading ---

  @doc """
  Load an existing session by ID.

  Only works if the agent advertised `loadSession: true` during initialize.
  """
  @spec load(session(), String.t()) :: {:ok, session()} | {:error, term()}
  def load(%__MODULE__{} = session, session_id) do
    if can_load_session?(session) do
      params = %{
        "sessionId" => session_id,
        "cwd" => session.workspace,
        "mcpServers" => session.mcp_servers
      }

      session = %{session | updates: [], prompt_accumulator: ""}

      case Agentic.Protocol.ACP.Client.request(session.client, "session/load", params,
             timeout: 30_000
           ) do
        {:ok, _result} ->
          loaded_session = %{session | session_id: session_id, updates: session.updates}
          {:ok, loaded_session}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :load_session_not_supported}
    end
  end

  # --- Set mode ---

  @doc "Switch the agent operating mode."
  @spec set_mode(session(), String.t()) :: :ok | {:error, term()}
  def set_mode(%__MODULE__{session_id: nil}, _mode_id), do: {:error, :no_session}

  def set_mode(%__MODULE__{} = session, mode_id) do
    params = %{
      "sessionId" => session.session_id,
      "modeId" => mode_id
    }

    case Agentic.Protocol.ACP.Client.request(session.client, "session/set_mode", params) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # --- Capability queries ---

  @doc "Check if the agent supports session loading."
  @spec can_load_session?(session()) :: boolean()
  def can_load_session?(%__MODULE__{agent_capabilities: nil}), do: false

  def can_load_session?(%__MODULE__{agent_capabilities: caps}) do
    Map.get(caps, "loadSession", false) == true
  end

  @doc "Check if the agent supports image input."
  @spec supports_image?(session()) :: boolean()
  def supports_image?(%__MODULE__{agent_capabilities: nil}), do: false

  def supports_image?(%__MODULE__{agent_capabilities: caps}) do
    get_in(caps, ["promptCapabilities", "image"]) == true
  end

  @doc "Check if the agent supports audio input."
  @spec supports_audio?(session()) :: boolean()
  def supports_audio?(%__MODULE__{agent_capabilities: nil}), do: false

  def supports_audio?(%__MODULE__{agent_capabilities: caps}) do
    get_in(caps, ["promptCapabilities", "audio"]) == true
  end

  # --- Private ---

  defp setup_notification_handler(session) do
    handler = fn method, params ->
      handle_update(session, method, params)
    end

    Agentic.Protocol.ACP.Client.request(session.client, "_set_notification_handler", %{
      "handler" => inspect(handler)
    })

    :ok
  end

  defp initialize(session, client_info, client_capabilities) do
    params = %{
      "protocolVersion" => 1,
      "clientCapabilities" => client_capabilities,
      "clientInfo" => client_info
    }

    case Agentic.Protocol.ACP.Client.request(session.client, "initialize", params,
           timeout: 10_000
         ) do
      {:ok, result} when is_map(result) ->
        Logger.info(
          "ACP initialized: protocol v#{result["protocolVersion"]}, " <>
            "agent: #{inspect(Map.get(result["agentInfo"], "name"))}"
        )

        {:ok, result}

      {:error, reason} ->
        {:error, {:initialize_failed, reason}}
    end
  end

  defp maybe_authenticate(_session, nil), do: :ok
  defp maybe_authenticate(_session, []), do: :ok

  defp maybe_authenticate(session, [_method | _rest] = methods) do
    Logger.info("ACP agent requires authentication, methods: #{inspect(methods)}")

    if auth_method = List.first(methods) do
      params = %{"methodId" => auth_method["id"]}

      case Agentic.Protocol.ACP.Client.request(session.client, "authenticate", params,
             timeout: 10_000
           ) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, {:authenticate_failed, reason}}
      end
    else
      :ok
    end
  end

  defp create_session(session) do
    params = %{
      "cwd" => session.workspace,
      "mcpServers" => session.mcp_servers
    }

    case Agentic.Protocol.ACP.Client.request(session.client, "session/new", params,
           timeout: 15_000
         ) do
      {:ok, %{"sessionId" => session_id}} ->
        Logger.info("ACP session created: #{session_id}")
        {:ok, session_id}

      {:ok, result} ->
        {:error, {:unexpected_session_response, result}}

      {:error, reason} ->
        {:error, {:session_create_failed, reason}}
    end
  end

  defp handle_update(_session, "session/update", params) do
    _ = params
    :ok
  end

  defp handle_update(_session, "session/request_permission", params) do
    _ = params
    :ok
  end

  defp handle_update(_session, _method, _params) do
    :ok
  end

  defp extract_tool_calls(updates) do
    updates
    |> Enum.filter(fn
      %{"update" => %{"sessionUpdate" => "tool_call"}} -> true
      _ -> false
    end)
    |> Enum.map(fn %{"update" => update} ->
      Types.tool_call_to_agentic(update)
    end)
  end
end
