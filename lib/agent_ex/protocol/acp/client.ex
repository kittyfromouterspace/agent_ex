defmodule AgentEx.Protocol.ACP.Client do
  @moduledoc """
  JSON-RPC 2.0 client over stdio for ACP communication.

  Manages bidirectional communication with an ACP agent subprocess.
  Handles request/response correlation, notification delivery, and
  incoming requests from the agent (e.g. permission requests).

  ## Architecture

  A listener process reads from the subprocess stdout and routes:
  - Responses (has "id") to waiting callers via `:persistent_term`
  - Notifications (no "id") to the registered notification handler
  - Incoming requests (has "id" and "method" from agent) to request handler

  ## Usage

      {:ok, client} = AgentEx.Protocol.ACP.Client.start_link(
        command: "kimi",
        args: ["acp"],
        env: %{}
      )

      {:ok, result} = AgentEx.Protocol.ACP.Client.request(client, "initialize", params)
      AgentEx.Protocol.ACP.Client.notify(client, "session/cancel", %{sessionId: "..."})
      AgentEx.Protocol.ACP.Client.stop(client)
  """

  use GenServer

  require Logger

  @type client :: pid()
  @type request_opts :: [timeout: non_neg_integer()]

  @default_timeout 30_000

  # --- Client API ---

  @doc """
  Start an ACP client that communicates with a subprocess.

  ## Options

    - `:command` - CLI binary path (required)
    - `:args` - List of arguments
    - `:env` - Extra environment variables (map)
    - `:notification_handler` - Function called with `(method, params)` for notifications
    - `:request_handler` - Function called with `(id, method, params)` for incoming requests, must return response
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Send a JSON-RPC request and wait for the response."
  @spec request(client(), String.t(), map(), request_opts()) ::
          {:ok, map()} | {:error, term()}
  def request(client, method, params \\ %{}, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    GenServer.call(client, {:request, method, params, timeout}, timeout + 5_000)
  end

  @doc "Send a JSON-RPC notification (no response expected)."
  @spec notify(client(), String.t(), map()) :: :ok
  def notify(client, method, params \\ %{}) do
    GenServer.cast(client, {:notify, method, params})
    :ok
  end

  @doc "Gracefully stop the client and terminate the subprocess."
  @spec stop(client()) :: :ok
  def stop(client) do
    GenServer.cast(client, :stop)
  end

  @doc "Get the command that was used to start this client."
  @spec command(client()) :: String.t()
  def command(client) do
    GenServer.call(client, :command, 5_000)
  catch
    :exit, _ -> nil
  end

  @doc "Reset the prompt accumulator and updates list."
  @spec reset_prompt_state(client()) :: :ok
  def reset_prompt_state(client) do
    GenServer.call(client, :reset_prompt_state, 5_000)
  end

  @doc "Get the current prompt accumulator text and updates list."
  @spec get_prompt_state(client()) :: {String.t(), [map()]}
  def get_prompt_state(client) do
    GenServer.call(client, :get_prompt_state, 5_000)
  end

  # --- Server Implementation ---

  @impl true
  def init(opts) do
    command = Keyword.fetch!(opts, :command)
    args = Keyword.get(opts, :args, [])
    env = Keyword.get(opts, :env, %{})
    notification_handler = Keyword.get(opts, :notification_handler)
    request_handler = Keyword.get(opts, :request_handler)

    executable = :os.find_executable(to_charlist(command)) || command

    port =
      Port.open(
        {:spawn_executable, executable},
        [:stream, :binary, :exit_status, {:args, args}, {:env, port_env(env)}]
      )

    state = %{
      port: port,
      command: command,
      buffer: "",
      next_id: 1,
      pending: %{},
      notification_handler: notification_handler,
      request_handler: request_handler,
      prompt_accumulator: "",
      updates: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:request, method, params, timeout}, from, state) do
    id = state.next_id

    msg =
      AgentEx.Protocol.ACP.Types.build_request(id, method, params)
      |> Jason.encode!()

    Port.command(state.port, [msg, "\n"])

    timer_ref = Process.send_after(self(), {:request_timeout, id}, timeout)

    new_pending =
      Map.put(state.pending, id, %{
        from: from,
        timer_ref: timer_ref
      })

    {:noreply, %{state | next_id: id + 1, pending: new_pending}}
  end

  @impl true
  def handle_call(:command, _from, state) do
    {:reply, state.command, state}
  end

  @impl true
  def handle_call(:get_prompt_state, _from, state) do
    {:reply, {state.prompt_accumulator, state.updates}, state}
  end

  @impl true
  def handle_call(:reset_prompt_state, _from, state) do
    {:reply, :ok, %{state | prompt_accumulator: "", updates: []}}
  end

  @impl true
  def handle_cast({:notify, method, params}, state) do
    msg =
      AgentEx.Protocol.ACP.Types.build_notification(method, params)
      |> Jason.encode!()

    Port.command(state.port, [msg, "\n"])

    {:noreply, state}
  end

  @impl true
  def handle_cast(:stop, state) do
    close_port(state.port)
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:request_timeout, id}, state) do
    case Map.pop(state.pending, id) do
      {nil, _} ->
        {:noreply, state}

      {%{from: from, timer_ref: _timer_ref}, new_pending} ->
        GenServer.reply(from, {:error, :timeout})
        {:noreply, %{state | pending: new_pending}}
    end
  end

  @impl true
  def handle_info({port, {:data, chunk}}, %{port: port} = state) do
    new_buffer = state.buffer <> chunk

    {messages, remaining} = extract_messages(new_buffer)

    state = Enum.reduce(messages, %{state | buffer: ""}, &dispatch_message/2)

    {:noreply, %{state | buffer: remaining}}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.info("ACP client (#{state.command}) exited with status #{status}")

    pending = state.pending

    for {_id, %{from: from}} <- pending do
      GenServer.reply(from, {:error, {:exit_status, status}})
    end

    {:noreply, %{state | pending: %{}, buffer: ""}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # --- Message dispatch ---

  defp dispatch_message(msg, state) do
    cond do
      AgentEx.Protocol.ACP.Types.response?(msg) ->
        handle_response(msg, state)

      AgentEx.Protocol.ACP.Types.notification?(msg) ->
        handle_notification(msg, state)

      AgentEx.Protocol.ACP.Types.request?(msg) ->
        handle_incoming_request(msg, state)

      true ->
        Logger.debug("ACP client: ignoring unknown message: #{inspect(msg)}")
        state
    end
  end

  defp handle_response(msg, state) do
    id = msg["id"]

    case Map.pop(state.pending, id) do
      {nil, _} ->
        Logger.debug("ACP client: received response for unknown request #{id}")
        state

      {%{from: from, timer_ref: timer_ref}, new_pending} ->
        Process.cancel_timer(timer_ref)

        result =
          if msg["error"] do
            error = msg["error"]
            {:error, %{code: error["code"], message: error["message"]}}
          else
            {:ok, msg["result"]}
          end

        GenServer.reply(from, result)
        %{state | pending: new_pending}
    end
  end

  defp handle_notification(msg, state) do
    if handler = state.notification_handler do
      try do
        handler.(msg["method"], msg["params"])
      rescue
        e ->
          Logger.warning("ACP client notification handler failed: #{inspect(e)}")
      end
    end

    # Accumulate prompt updates in client state
    state = accumulate_update(msg, state)

    state
  end

  defp accumulate_update(%{"method" => "session/update", "params" => params} = msg, state) do
    update = params["update"] || %{}
    type = update["sessionUpdate"] || ""

    prompt_accumulator =
      case type do
        "agent_message_chunk" ->
          text = get_in(update, ["content", "text"]) || ""

          # ACP agents may send either incremental chunks or the full message
          # so far. Handle both by checking if the new text is a superset of
          # the accumulated text.
          new_acc =
            cond do
              text == state.prompt_accumulator ->
                state.prompt_accumulator

              String.starts_with?(text, state.prompt_accumulator) ->
                text

              true ->
                state.prompt_accumulator <> text
            end

          Logger.debug(
            "ACP chunk: prev_len=#{String.length(state.prompt_accumulator)}, new_len=#{String.length(new_acc)}, text_len=#{String.length(text)}"
          )

          new_acc

        _ ->
          state.prompt_accumulator
      end

    %{state | prompt_accumulator: prompt_accumulator, updates: state.updates ++ [msg]}
  end

  defp accumulate_update(_msg, state) do
    state
  end

  defp handle_incoming_request(msg, state) do
    id = msg["id"]
    method = msg["method"]
    params = msg["params"] || %{}

    if handler = state.request_handler do
      spawn(fn ->
        response =
          try do
            handler.(id, method, params)
          rescue
            e ->
              Logger.warning("ACP client request handler failed for #{method}: #{inspect(e)}")

              AgentEx.Protocol.ACP.Types.build_error(
                id,
                -32_603,
                "Internal error: #{Exception.message(e)}"
              )
          end

        send_json(state.port, response)
      end)
    else
      Logger.debug("ACP client: received request #{method} but no request_handler set")
    end

    state
  end

  # --- Message extraction ---

  defp extract_messages(buffer) do
    extract_messages(buffer, [])
  end

  defp extract_messages(buffer, acc) do
    case String.split(buffer, "\n", parts: 2) do
      [line, rest] ->
        line = String.trim(line)

        if line == "" do
          extract_messages(rest, acc)
        else
          case AgentEx.Protocol.ACP.Types.parse_message(line) do
            {:ok, msg} ->
              extract_messages(rest, [msg | acc])

            {:error, reason} ->
              Logger.debug("ACP client: failed to parse message: #{inspect(reason)}")
              extract_messages(rest, acc)
          end
        end

      _ ->
        {Enum.reverse(acc), buffer}
    end
  end

  # --- Helpers ---

  defp send_json(port, msg) do
    json = Jason.encode!(msg)
    Port.command(port, [json, "\n"])
  end

  defp close_port(port) do
    try do
      Port.close(port)
    rescue
      _ -> :ok
    end
  end

  defp port_env(env) do
    env
    |> Enum.map(fn {k, v} ->
      {String.to_charlist(to_string(k)), String.to_charlist(to_string(v))}
    end)
  end
end
