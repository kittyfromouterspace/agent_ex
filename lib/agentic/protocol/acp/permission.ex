defmodule Agentic.Protocol.ACP.Permission do
  @moduledoc """
  Bridges ACP permission requests to Agentic tool permission system.

  When an ACP agent sends a `session/request_permission` request, this module
  translates between ACP's permission option model and Agentic's `tool_permissions`
  map.

  ## Permission Policies

    - `:ask` -- Delegate to the host application via callback
    - `:allow_all` -- Always approve (auto-approve all tool calls)
    - `:deny_all` -- Always reject
  """

  alias Agentic.Protocol.ACP.Types

  @doc """
  Handle an incoming permission request from the agent.

  Returns the ACP response map to send back to the agent.
  """
  @spec handle_request(
          map(),
          Types.permission_option() | nil,
          atom(),
          map() | nil
        ) :: map()
  def handle_request(request, options, policy, callbacks) do
    request_id = request["id"]
    tool_call = Map.get(request, "params", %{})["toolCall"]
    tool_call_id = Map.get(tool_call || %{}, "toolCallId", "unknown")

    decision =
      case policy do
        :allow_all -> auto_allow(options, tool_call_id)
        :deny_all -> auto_deny(options, tool_call_id)
        :ask -> delegate_to_callback(options, tool_call_id, callbacks)
      end

    Types.build_response(request_id, %{"outcome" => decision})
  end

  @doc "Build an allow-once outcome."
  @spec auto_allow([Types.permission_option()] | nil, String.t()) :: map()
  def auto_allow(options, _tool_call_id) do
    option_id =
      find_option_by_kind(options, "allow_once") || find_option_by_kind(options, "allow_always")

    if option_id do
      %{"outcome" => "selected", "optionId" => option_id}
    else
      %{"outcome" => "selected", "optionId" => "allow-once"}
    end
  end

  @doc "Build a deny-once outcome."
  @spec auto_deny([Types.permission_option()] | nil, String.t()) :: map()
  def auto_deny(options, _tool_call_id) do
    option_id =
      find_option_by_kind(options, "reject_once") || find_option_by_kind(options, "reject_always")

    if option_id do
      %{"outcome" => "selected", "optionId" => option_id}
    else
      %{"outcome" => "selected", "optionId" => "reject-once"}
    end
  end

  @doc "Delegate permission decision to a callback."
  @spec delegate_to_callback([Types.permission_option()] | nil, String.t(), map() | nil) :: map()
  def delegate_to_callback(options, tool_call_id, callbacks) do
    if callback = callbacks && Map.get(callbacks, "acp_permission_request") do
      try do
        case callback.(tool_call_id, options || []) do
          :allow -> auto_allow(options, tool_call_id)
          :deny -> auto_deny(options, tool_call_id)
          {:allow, option_id} -> %{"outcome" => "selected", "optionId" => option_id}
          {:deny, option_id} -> %{"outcome" => "selected", "optionId" => option_id}
          outcome when is_map(outcome) -> outcome
        end
      rescue
        _ ->
          auto_deny(options, tool_call_id)
      end
    else
      auto_allow(options, tool_call_id)
    end
  end

  defp find_option_by_kind(nil, _kind), do: nil

  defp find_option_by_kind(options, kind) do
    Enum.find_value(options, fn
      %{"kind" => ^kind, "optionId" => id} -> id
      _ -> nil
    end)
  end
end
