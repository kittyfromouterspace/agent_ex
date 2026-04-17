defmodule Agentic.Protocol.ACP do
  @moduledoc """
  Generic ACP (Agent Client Protocol) implementation.

  Implements `Agentic.AgentProtocol` for any ACP-compatible agent.
  One module handles all ACP agents -- the agent identity (kimi, cursor, etc.)
  is specified via backend config, not via separate modules.

  ## Usage

      # Direct use
      {:ok, session_id} = Agentic.Protocol.ACP.start(
        %{command: "kimi", args: ["acp"], workspace: "/path"},
        context
      )

      # Via registry
      Agentic.Protocol.Registry.register({:acp, :kimi}, Agentic.Protocol.ACP)
      {:ok, module} = Agentic.Protocol.Registry.lookup({:acp, :kimi})

  ## Backend Config

      %{
        command: "kimi",           # CLI binary name
        args: ["acp"],             # Arguments to enable ACP mode
        env: %{},                  # Extra environment variables
        workspace: "/path/to/dir", # Working directory (cwd)
        mcp_servers: [],           # MCP servers to forward to agent
        permission_policy: :ask    # :ask | :allow_all | :deny_all
      }
  """

  use Agentic.AgentProtocol

  alias Agentic.Protocol.ACP.Types
  alias Agentic.Protocol.ACP.Session

  require Logger

  @default_timeout 120_000

  # --- AgentProtocol callbacks ---

  @impl true
  def transport_type, do: :acp

  @impl true
  def available? do
    true
  end

  @doc """
  Check availability for a specific agent command.

  Unlike other protocols, ACP availability depends on the command
  specified in the backend config. Use `available_for?/1` to check.
  """
  @spec available_for?(String.t()) :: boolean()
  def available_for?(command) do
    System.find_executable(command) != nil
  end

  @impl true
  def start(backend_config, _ctx) do
    command = backend_config[:command] || raise ":command required in backend_config"
    args = backend_config[:args] || ["acp"]
    env = backend_config[:env] || %{}
    workspace = backend_config[:workspace] || File.cwd!()
    mcp_servers = backend_config[:mcp_servers] || []
    permission_policy = backend_config[:permission_policy] || :ask

    notification_handler = make_notification_handler()

    request_handler = make_request_handler(permission_policy, backend_config[:callbacks])

    client_opts = [
      command: command,
      args: args,
      env: env,
      notification_handler: notification_handler,
      request_handler: request_handler
    ]

    case Agentic.Protocol.ACP.Client.start_link(client_opts) do
      {:ok, client} ->
        connect_opts = [
          client: client,
          workspace: workspace,
          permission_policy: permission_policy,
          mcp_servers: mcp_servers
        ]

        case Session.connect(connect_opts) do
          {:ok, session} ->
            session_id = session.session_id

            :persistent_term.put({__MODULE__, session_id}, %{
              session: session,
              backend_config: backend_config
            })

            Logger.info("ACP session started: #{session_id} (#{command})")
            {:ok, session_id}

          {:error, reason} ->
            Agentic.Protocol.ACP.Client.stop(client)
            {:error, {:connect_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:client_start_failed, reason}}
    end
  end

  @impl true
  def send(session_id, messages, ctx) do
    with {:ok, state} <- fetch_session(session_id) do
      session = state.session
      content_blocks = Types.messages_to_content_blocks(messages)
      _callbacks = ctx.callbacks || %{}

      case Session.prompt(session, content_blocks, timeout: @default_timeout) do
        {:ok, response, updated_session} ->
          update_session(session_id, state, updated_session)

          protocol_response = %{
            content: response.content,
            tool_calls: response.tool_calls,
            usage: %{},
            stop_reason: response.stop_reason,
            metadata: %{
              session_id: session_id,
              protocol: :acp,
              updates: response.updates
            }
          }

          {:ok, protocol_response}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @impl true
  def resume(session_id, messages, ctx) do
    case send(session_id, messages, ctx) do
      {:ok, response} -> {:ok, session_id, response}
      error -> error
    end
  end

  @impl true
  def stop(session_id) do
    try do
      case :persistent_term.get({__MODULE__, session_id}, nil) do
        nil ->
          :ok

        %{session: session} ->
          Session.close(session, [])
          :persistent_term.erase({__MODULE__, session_id})
          Logger.info("ACP session stopped: #{session_id}")
          :ok
      end
    rescue
      _ -> :ok
    end
  end

  @impl true
  def parse_stream(chunk) do
    case Types.parse_message(chunk) do
      {:ok, msg} ->
        if Types.notification?(msg) do
          case msg["method"] do
            "session/update" ->
              update = Map.get(msg, "params", %{})["update"] || %{}
              type = Map.get(update, "sessionUpdate", "")

              case type do
                "agent_message_chunk" ->
                  text = get_in(update, ["content", "text"]) || ""
                  {:message, %{"content" => text}}

                "tool_call" ->
                  {:message, %{"tool_calls" => [Types.tool_call_to_agentex(update)]}}

                _ ->
                  :partial
              end

            _ ->
              :partial
          end
        else
          :partial
        end

      _ ->
        :partial
    end
  end

  @impl true
  def format_messages(messages, _ctx) do
    Types.messages_to_content_blocks(messages)
    |> Jason.encode!()
  end

  # --- Private ---

  defp fetch_session(session_id) do
    case :persistent_term.get({__MODULE__, session_id}, nil) do
      nil -> {:error, :session_not_found}
      state -> {:ok, state}
    end
  end

  defp update_session(session_id, old_state, new_session) do
    :persistent_term.put({__MODULE__, session_id}, %{
      session: new_session,
      backend_config: old_state.backend_config
    })
  end

  defp make_notification_handler do
    fn method, params ->
      case method do
        "session/update" ->
          update = Map.get(params, "update", %{})
          type = Map.get(update, "sessionUpdate", "")

          if type in ["agent_message_chunk", "tool_call", "tool_call_update"] do
            :telemetry.execute(
              [:agentic, :acp, :session_update],
              %{type: type},
              %{}
            )
          end

        _ ->
          :ok
      end
    end
  end

  defp make_request_handler(permission_policy, callbacks) do
    fn id, method, params ->
      case method do
        "session/request_permission" ->
          Agentic.Protocol.ACP.Permission.handle_request(
            %{"id" => id, "params" => params},
            Map.get(params, "options"),
            permission_policy,
            callbacks
          )

        "fs/read_text_file" ->
          handle_fs_read(id, params, callbacks)

        "fs/write_text_file" ->
          handle_fs_write(id, params, callbacks)

        _ ->
          Types.build_error(id, -32_601, "Method not implemented: #{method}")
      end
    end
  end

  defp handle_fs_read(id, params, callbacks) do
    path = Map.get(params, "path", "")
    line = Map.get(params, "line")
    limit = Map.get(params, "limit")

    if callback = get_in(callbacks || %{}, [:acp_fs_read]) do
      case callback.(path, line, limit) do
        {:ok, content} ->
          Types.build_response(id, %{"content" => content})

        {:error, reason} ->
          Types.build_error(id, -32_602, "File read failed: #{inspect(reason)}")
      end
    else
      Types.build_error(id, -32_602, "fs/read_text_file not supported by host")
    end
  end

  defp handle_fs_write(id, params, callbacks) do
    path = Map.get(params, "path", "")
    content = Map.get(params, "content", "")

    if callback = get_in(callbacks || %{}, [:acp_fs_write]) do
      case callback.(path, content) do
        :ok ->
          Types.build_response(id, nil)

        {:error, reason} ->
          Types.build_error(id, -32_602, "File write failed: #{inspect(reason)}")
      end
    else
      Types.build_error(id, -32_602, "fs/write_text_file not supported by host")
    end
  end
end
