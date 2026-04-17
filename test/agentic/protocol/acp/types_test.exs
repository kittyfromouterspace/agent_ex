defmodule Agentic.Protocol.ACP.TypesTest do
  use ExUnit.Case, async: true

  alias Agentic.Protocol.ACP.Types

  describe "parse_stop_reason/1" do
    test "parses known stop reasons" do
      assert Types.parse_stop_reason("end_turn") == :end_turn
      assert Types.parse_stop_reason("max_tokens") == :max_tokens
      assert Types.parse_stop_reason("max_turn_requests") == :max_turn_requests
      assert Types.parse_stop_reason("refusal") == :refusal
      assert Types.parse_stop_reason("cancelled") == :cancelled
    end

    test "returns raw string for unknown reasons" do
      assert Types.parse_stop_reason("unknown_reason") == "unknown_reason"
    end
  end

  describe "parse_tool_kind/1" do
    test "parses known tool kinds" do
      assert Types.parse_tool_kind("read") == :read
      assert Types.parse_tool_kind("edit") == :edit
      assert Types.parse_tool_kind("delete") == :delete
      assert Types.parse_tool_kind("move") == :move
      assert Types.parse_tool_kind("search") == :search
      assert Types.parse_tool_kind("execute") == :execute
      assert Types.parse_tool_kind("think") == :think
      assert Types.parse_tool_kind("fetch") == :fetch
    end

    test "returns :other for unknown kinds" do
      assert Types.parse_tool_kind("something") == :other
      assert Types.parse_tool_kind("custom") == :other
    end
  end

  describe "parse_tool_status/1" do
    test "parses known tool statuses" do
      assert Types.parse_tool_status("pending") == :pending
      assert Types.parse_tool_status("in_progress") == :in_progress
      assert Types.parse_tool_status("completed") == :completed
      assert Types.parse_tool_status("failed") == :failed
    end

    test "returns :pending for unknown statuses" do
      assert Types.parse_tool_status("running") == :pending
    end
  end

  describe "parse_permission_kind/1" do
    test "parses all permission kinds" do
      assert Types.parse_permission_kind("allow_once") == :allow_once
      assert Types.parse_permission_kind("allow_always") == :allow_always
      assert Types.parse_permission_kind("reject_once") == :reject_once
      assert Types.parse_permission_kind("reject_always") == :reject_always
    end
  end

  describe "messages_to_content_blocks/1" do
    test "converts user messages" do
      messages = [
        %{"role" => "user", "content" => "Hello world"}
      ]

      assert Types.messages_to_content_blocks(messages) ==
               [%{"type" => "text", "text" => "Hello world"}]
    end

    test "converts assistant messages" do
      messages = [
        %{"role" => "assistant", "content" => "I can help"}
      ]

      assert Types.messages_to_content_blocks(messages) ==
               [%{"type" => "text", "text" => "I can help"}]
    end

    test "skips system messages" do
      messages = [
        %{"role" => "system", "content" => "You are helpful"},
        %{"role" => "user", "content" => "Hi"}
      ]

      assert Types.messages_to_content_blocks(messages) ==
               [%{"type" => "text", "text" => "Hi"}]
    end

    test "skips empty content" do
      messages = [
        %{"role" => "user", "content" => ""},
        %{"role" => "user", "content" => "Hello"}
      ]

      assert Types.messages_to_content_blocks(messages) ==
               [%{"type" => "text", "text" => "Hello"}]
    end

    test "handles multiple messages" do
      messages = [
        %{"role" => "user", "content" => "First"},
        %{"role" => "assistant", "content" => "Second"},
        %{"role" => "user", "content" => "Third"}
      ]

      assert length(Types.messages_to_content_blocks(messages)) == 3
    end

    test "handles empty message list" do
      assert Types.messages_to_content_blocks([]) == []
    end
  end

  describe "content_block_to_text/1" do
    test "extracts text from text block" do
      assert Types.content_block_to_text(%{"type" => "text", "text" => "hello"}) == "hello"
    end

    test "returns empty for non-text block" do
      assert Types.content_block_to_text(%{"type" => "image", "data" => "abc"}) == ""
    end

    test "handles nil text" do
      assert Types.content_block_to_text(%{"type" => "text", "text" => nil}) == ""
    end
  end

  describe "tool_call_to_agentic/1" do
    test "converts completed tool call with rawInput" do
      update = %{
        "toolCallId" => "call_001",
        "status" => "completed",
        "rawInput" => %{"name" => "read_file", "arguments" => %{"path" => "/tmp/test"}}
      }

      result = Types.tool_call_to_agentic(update)

      assert result["id"] == "call_001"
      assert result["type"] == "function"
      assert result["function"]["name"] == "read_file"
    end

    test "converts tool call with title but no rawInput" do
      update = %{
        "toolCallId" => "call_002",
        "title" => "Reading file"
      }

      result = Types.tool_call_to_agentic(update)

      assert result["id"] == "call_002"
      assert result["function"]["name"] == "unknown"
    end

    test "converts minimal tool call" do
      update = %{"toolCallId" => "call_003"}

      result = Types.tool_call_to_agentic(update)

      assert result["id"] == "call_003"
      assert result["function"]["name"] == "unknown"
    end
  end

  describe "JSON-RPC helpers" do
    test "build_request/3" do
      req = Types.build_request(1, "initialize", %{"protocolVersion" => 1})

      assert req["jsonrpc"] == "2.0"
      assert req["id"] == 1
      assert req["method"] == "initialize"
      assert req["params"]["protocolVersion"] == 1
    end

    test "build_notification/2" do
      notif = Types.build_notification("session/cancel", %{"sessionId" => "abc"})

      assert notif["jsonrpc"] == "2.0"
      refute Map.has_key?(notif, "id")
      assert notif["method"] == "session/cancel"
    end

    test "build_response/2" do
      resp = Types.build_response(1, %{"sessionId" => "abc"})

      assert resp["jsonrpc"] == "2.0"
      assert resp["id"] == 1
      assert resp["result"]["sessionId"] == "abc"
      refute Map.has_key?(resp, "error")
    end

    test "build_error/4" do
      err = Types.build_error(1, -32000, "Auth required", "details")

      assert err["jsonrpc"] == "2.0"
      assert err["id"] == 1
      assert err["error"]["code"] == -32000
      assert err["error"]["message"] == "Auth required"
      assert err["error"]["data"] == "details"
    end

    test "build_error/3 without data" do
      err = Types.build_error(1, -32600, "Invalid params")

      refute Map.has_key?(err["error"], "data")
    end
  end

  describe "parse_message/1" do
    test "parses valid JSON-RPC request" do
      json = ~s({"jsonrpc":"2.0","id":1,"method":"initialize","params":{}})

      assert {:ok, msg} = Types.parse_message(json)
      assert msg["jsonrpc"] == "2.0"
      assert msg["id"] == 1
    end

    test "parses valid JSON-RPC notification" do
      json = ~s({"jsonrpc":"2.0","method":"session/update","params":{}})

      assert {:ok, msg} = Types.parse_message(json)
      refute Map.has_key?(msg, "id")
    end

    test "rejects non-JSON" do
      assert {:error, _} = Types.parse_message("not json")
    end

    test "rejects JSON without jsonrpc field" do
      json = ~s({"id":1,"method":"test"})
      assert {:error, :invalid_jsonrpc} = Types.parse_message(json)
    end

    test "rejects wrong jsonrpc version" do
      json = ~s({"jsonrpc":"1.0","id":1})
      assert {:error, :invalid_jsonrpc} = Types.parse_message(json)
    end
  end

  describe "message classification" do
    test "request?/1" do
      assert Types.request?(%{"jsonrpc" => "2.0", "id" => 1, "method" => "test"})
      refute Types.request?(%{"jsonrpc" => "2.0", "method" => "test"})
      refute Types.request?(%{"jsonrpc" => "2.0", "id" => 1, "result" => %{}})
    end

    test "notification?/1" do
      assert Types.notification?(%{"jsonrpc" => "2.0", "method" => "test"})
      refute Types.notification?(%{"jsonrpc" => "2.0", "id" => 1, "method" => "test"})
    end

    test "response?/1" do
      assert Types.response?(%{"jsonrpc" => "2.0", "id" => 1, "result" => %{}})
      assert Types.response?(%{"jsonrpc" => "2.0", "id" => 1, "error" => %{}})
      refute Types.response?(%{"jsonrpc" => "2.0", "id" => 1, "method" => "test"})
    end
  end
end
