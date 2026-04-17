defmodule Agentic.Protocol.ACP.PermissionTest do
  use ExUnit.Case, async: true

  alias Agentic.Protocol.ACP.Permission

  defp make_request(opts \\ %{}) do
    Map.merge(
      %{
        "id" => 5,
        "params" => %{
          "sessionId" => "sess_abc",
          "toolCall" => %{"toolCallId" => "call_001"},
          "options" => [
            %{"optionId" => "allow-once", "name" => "Allow once", "kind" => "allow_once"},
            %{"optionId" => "reject-once", "name" => "Reject", "kind" => "reject_once"}
          ]
        }
      },
      opts
    )
  end

  describe "handle_request/4" do
    test "auto-allow selects first allow option" do
      request = make_request()
      result = Permission.handle_request(request, request["params"]["options"], :allow_all, nil)

      assert result["result"]["outcome"]["outcome"] == "selected"
      assert result["result"]["outcome"]["optionId"] == "allow-once"
    end

    test "auto-deny selects first reject option" do
      request = make_request()
      result = Permission.handle_request(request, request["params"]["options"], :deny_all, nil)

      assert result["result"]["outcome"]["outcome"] == "selected"
      assert result["result"]["outcome"]["optionId"] == "reject-once"
    end

    test "auto-allow falls back to allow_always when allow_once missing" do
      request =
        make_request(%{
          "params" => %{
            "sessionId" => "sess_abc",
            "toolCall" => %{"toolCallId" => "call_001"},
            "options" => [
              %{"optionId" => "allow-always", "name" => "Always", "kind" => "allow_always"}
            ]
          }
        })

      result = Permission.handle_request(request, request["params"]["options"], :allow_all, nil)

      assert result["result"]["outcome"]["optionId"] == "allow-always"
    end

    test "auto-allow uses hardcoded fallback when no options match" do
      request = make_request(%{"params" => %{"options" => []}})
      result = Permission.handle_request(request, [], :allow_all, nil)

      assert result["result"]["outcome"]["optionId"] == "allow-once"
    end

    test "auto-deny uses hardcoded fallback when no options match" do
      request = make_request(%{"params" => %{"options" => []}})
      result = Permission.handle_request(request, [], :deny_all, nil)

      assert result["result"]["outcome"]["optionId"] == "reject-once"
    end

    test "delegate_to_callback calls callback with tool_call_id" do
      callback = fn _tool_call_id, _options -> :allow end
      request = make_request()

      result =
        Permission.handle_request(
          request,
          request["params"]["options"],
          :ask,
          %{"acp_permission_request" => callback}
        )

      assert result["result"]["outcome"]["outcome"] == "selected"
      assert result["result"]["outcome"]["optionId"] == "allow-once"
    end

    test "delegate_to_callback handles :deny" do
      callback = fn _tool_call_id, _options -> :deny end
      request = make_request()

      result =
        Permission.handle_request(
          request,
          request["params"]["options"],
          :ask,
          %{"acp_permission_request" => callback}
        )

      assert result["result"]["outcome"]["outcome"] == "selected"
      assert result["result"]["outcome"]["optionId"] == "reject-once"
    end

    test "delegate_to_callback handles {:allow, option_id}" do
      callback = fn _tool_call_id, _options -> {:allow, "allow-always"} end
      request = make_request()

      result =
        Permission.handle_request(
          request,
          request["params"]["options"],
          :ask,
          %{"acp_permission_request" => callback}
        )

      assert result["result"]["outcome"]["outcome"] == "selected"
      assert result["result"]["outcome"]["optionId"] == "allow-always"
    end

    test "delegate_to_callback falls back to deny on error" do
      callback = fn _, _ -> raise "boom" end
      request = make_request()

      result =
        Permission.handle_request(
          request,
          request["params"]["options"],
          :ask,
          %{"acp_permission_request" => callback}
        )

      assert result["result"]["outcome"]["outcome"] == "selected"
      assert result["result"]["outcome"]["optionId"] == "reject-once"
    end

    test "delegate_to_callback defaults to allow when no callback" do
      request = make_request()

      result =
        Permission.handle_request(
          request,
          request["params"]["options"],
          :ask,
          nil
        )

      assert result["result"]["outcome"]["outcome"] == "selected"
      assert result["result"]["outcome"]["optionId"] == "allow-once"
    end

    test "handles nil options" do
      request = make_request(%{"params" => %{"options" => nil}})
      result = Permission.handle_request(request, nil, :allow_all, nil)

      assert result["result"]["outcome"]["optionId"] == "allow-once"
    end
  end
end
