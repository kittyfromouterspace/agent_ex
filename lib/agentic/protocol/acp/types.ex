defmodule Agentic.Protocol.ACP.Types do
  @moduledoc """
  ACP (Agent Client Protocol) type definitions and conversions.

  Defines the core types from the ACP specification and provides
  conversion functions between ACP wire format and Agentic internal format.

  Wire format uses string keys (ACP is JSON-based).
  Agentic internal format uses atom keys in structs.

  Reference: https://agentclientprotocol.com/protocol/schema.md
  """

  @type protocol_version :: pos_integer()
  @type session_id :: String.t()
  @type request_id :: pos_integer()

  @type stop_reason :: :end_turn | :max_tokens | :max_turn_requests | :refusal | :cancelled
  @type tool_kind ::
          :read | :edit | :delete | :move | :search | :execute | :think | :fetch | :other
  @type tool_status :: :pending | :in_progress | :completed | :failed
  @type permission_kind :: :allow_once | :allow_always | :reject_once | :reject_always

  @type content_block :: %{
          String.t() => term()
        }

  @type session_update_type ::
          :agent_message_chunk
          | :user_message_chunk
          | :tool_call
          | :tool_call_update
          | :plan
          | :available_commands_update
          | :config_option_update
          | :current_mode_update

  @type tool_call_content :: %{
          String.t() => term()
        }

  @type tool_call_update :: %{
          String.t() => term()
        }

  @type session_update :: %{
          String.t() => term()
        }

  @type agent_capabilities :: map()

  @type client_capabilities :: map()

  @type permission_option :: %{
          String.t() => String.t()
        }

  @type json_rpc_message :: %{
          String.t() => term()
        }

  # --- Stop Reason conversion ---

  @doc "Parses a stop reason string from ACP wire format to atom."
  @spec parse_stop_reason(String.t()) :: stop_reason()
  def parse_stop_reason("end_turn"), do: :end_turn
  def parse_stop_reason("max_tokens"), do: :max_tokens
  def parse_stop_reason("max_turn_requests"), do: :max_turn_requests
  def parse_stop_reason("refusal"), do: :refusal
  def parse_stop_reason("cancelled"), do: :cancelled
  def parse_stop_reason(other), do: other

  # --- Tool Kind conversion ---

  @doc "Parses a tool kind string from ACP wire format to atom."
  @spec parse_tool_kind(String.t()) :: tool_kind()
  def parse_tool_kind("read"), do: :read
  def parse_tool_kind("edit"), do: :edit
  def parse_tool_kind("delete"), do: :delete
  def parse_tool_kind("move"), do: :move
  def parse_tool_kind("search"), do: :search
  def parse_tool_kind("execute"), do: :execute
  def parse_tool_kind("think"), do: :think
  def parse_tool_kind("fetch"), do: :fetch
  def parse_tool_kind(_), do: :other

  # --- Tool Status conversion ---

  @doc "Parses a tool status string from ACP wire format to atom."
  @spec parse_tool_status(String.t()) :: tool_status()
  def parse_tool_status("pending"), do: :pending
  def parse_tool_status("in_progress"), do: :in_progress
  def parse_tool_status("completed"), do: :completed
  def parse_tool_status("failed"), do: :failed
  def parse_tool_status(_), do: :pending

  # --- Permission Kind conversion ---

  @doc "Parses a permission kind string from ACP wire format to atom."
  @spec parse_permission_kind(String.t()) :: permission_kind()
  def parse_permission_kind("allow_once"), do: :allow_once
  def parse_permission_kind("allow_always"), do: :allow_always
  def parse_permission_kind("reject_once"), do: :reject_once
  def parse_permission_kind("reject_always"), do: :reject_always

  # --- Session Update type conversion ---

  @doc "Parses a session update type string to atom."
  @spec parse_session_update_type(String.t()) :: session_update_type()
  def parse_session_update_type("agent_message_chunk"), do: :agent_message_chunk
  def parse_session_update_type("user_message_chunk"), do: :user_message_chunk
  def parse_session_update_type("tool_call"), do: :tool_call
  def parse_session_update_type("tool_call_update"), do: :tool_call_update
  def parse_session_update_type("plan"), do: :plan
  def parse_session_update_type("available_commands_update"), do: :available_commands_update
  def parse_session_update_type("config_option_update"), do: :config_option_update
  def parse_session_update_type("current_mode_update"), do: :current_mode_update

  # --- Message conversion: Agentic -> ACP ---

  @doc """
  Converts Agentic messages to ACP ContentBlock[] format.

  Agentic messages use `%{"role" => ..., "content" => ...}` with string keys.
  ACP prompts use ContentBlock[] with `type`, `text`, etc.
  """
  @spec messages_to_content_blocks([map()]) :: [content_block()]
  def messages_to_content_blocks(messages) do
    messages
    |> Enum.flat_map(fn
      %{"role" => "system"} ->
        []

      %{"role" => "user", "content" => content} when is_binary(content) ->
        if content == "" do
          []
        else
          [%{"type" => "text", "text" => content}]
        end

      %{"role" => "assistant", "content" => content} when is_binary(content) ->
        if content == "" do
          []
        else
          [%{"type" => "text", "text" => content}]
        end

      %{"role" => _role, "content" => content} when is_binary(content) ->
        [%{"type" => "text", "text" => content}]

      %{"role" => _role} ->
        []
    end)
  end

  # --- Message conversion: ACP -> Agentic ---

  @doc """
  Extracts text content from an ACP ContentBlock.

  Returns the text string or empty string if not a text block.
  """
  @spec content_block_to_text(content_block()) :: String.t()
  def content_block_to_text(%{"type" => "text", "text" => text}), do: text || ""
  def content_block_to_text(_), do: ""

  # --- Tool call conversion: ACP -> Agentic ---

  @doc """
  Converts an ACP tool_call_update to Agentic pending_tool_call format.
  """
  @spec tool_call_to_agentex(tool_call_update()) :: map()
  def tool_call_to_agentex(%{
        "toolCallId" => id,
        "status" => "completed",
        "rawInput" => raw_input
      }) do
    name = Map.get(raw_input || %{}, "name", "unknown")

    %{
      "id" => id,
      "type" => "function",
      "function" => %{
        "name" => name,
        "arguments" => Jason.encode!(Map.get(raw_input || %{}, "arguments", %{}))
      }
    }
  end

  def tool_call_to_agentex(%{
        "toolCallId" => id,
        "rawInput" => raw_input,
        "title" => title
      }) do
    name = Map.get(raw_input || %{}, "name", "unknown")

    %{
      "id" => id,
      "type" => "function",
      "function" => %{
        "name" => name,
        "arguments" => Jason.encode!(Map.get(raw_input || %{}, "arguments", %{}))
      },
      "title" => title
    }
  end

  def tool_call_to_agentex(%{"toolCallId" => id}) do
    %{
      "id" => id,
      "type" => "function",
      "function" => %{
        "name" => "unknown",
        "arguments" => "{}"
      }
    }
  end

  # --- JSON-RPC helpers ---

  @doc "Builds a JSON-RPC request message."
  @spec build_request(request_id(), String.t(), map()) :: map()
  def build_request(id, method, params) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "method" => method,
      "params" => params
    }
  end

  @doc "Builds a JSON-RPC notification message (no id, no response expected)."
  @spec build_notification(String.t(), map()) :: map()
  def build_notification(method, params) do
    %{
      "jsonrpc" => "2.0",
      "method" => method,
      "params" => params
    }
  end

  @doc "Builds a JSON-RPC success response."
  @spec build_response(request_id(), term()) :: map()
  def build_response(id, result) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => result
    }
  end

  @doc "Builds a JSON-RPC error response."
  @spec build_error(request_id(), integer(), String.t(), term()) :: map()
  def build_error(id, code, message, data \\ nil) do
    error = %{"code" => code, "message" => message}

    error =
      if data do
        Map.put(error, "data", data)
      else
        error
      end

    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => error
    }
  end

  @doc "Parses a JSON string into a JSON-RPC message."
  @spec parse_message(String.t()) :: {:ok, json_rpc_message()} | {:error, term()}
  def parse_message(json) do
    case Jason.decode(json) do
      {:ok, msg} when is_map(msg) ->
        if Map.get(msg, "jsonrpc") == "2.0" do
          {:ok, msg}
        else
          {:error, :invalid_jsonrpc}
        end

      {:error, _} = err ->
        err

      _ ->
        {:error, :not_a_map}
    end
  end

  @doc "Returns true if the JSON-RPC message is a request (has id and method)."
  @spec request?(json_rpc_message()) :: boolean()
  def request?(msg) do
    is_map(msg) and Map.has_key?(msg, "id") and Map.has_key?(msg, "method")
  end

  @doc "Returns true if the JSON-RPC message is a notification (no id)."
  @spec notification?(json_rpc_message()) :: boolean()
  def notification?(msg) do
    is_map(msg) and not Map.has_key?(msg, "id") and Map.has_key?(msg, "method")
  end

  @doc "Returns true if the JSON-RPC message is a response (has id and result/error)."
  @spec response?(json_rpc_message()) :: boolean()
  def response?(msg) do
    is_map(msg) and Map.has_key?(msg, "id") and
      (Map.has_key?(msg, "result") or Map.has_key?(msg, "error"))
  end
end
