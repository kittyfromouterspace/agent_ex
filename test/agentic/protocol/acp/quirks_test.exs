defmodule Agentic.Protocol.ACP.QuirksTest do
  use ExUnit.Case, async: true

  alias Agentic.Protocol.ACP.Quirks

  describe "infer_tool_kind/1" do
    test "infers read from common read patterns" do
      assert Quirks.infer_tool_kind("read_file") == :read
      assert Quirks.infer_tool_kind("view source code") == :read
      assert Quirks.infer_tool_kind("Open project") == :read
      assert Quirks.infer_tool_kind("get weather") == :read
    end

    test "infers edit from common edit patterns" do
      assert Quirks.infer_tool_kind("edit file") == :edit
      assert Quirks.infer_tool_kind("write to file") == :edit
      assert Quirks.infer_tool_kind("modify config") == :edit
      assert Quirks.infer_tool_kind("create component") == :edit
    end

    test "infers delete from delete patterns" do
      assert Quirks.infer_tool_kind("delete file") == :delete
      assert Quirks.infer_tool_kind("remove old code") == :delete
    end

    test "infers execute from shell patterns" do
      assert Quirks.infer_tool_kind("bash: run tests") == :execute
      assert Quirks.infer_tool_kind("run command") == :execute
      assert Quirks.infer_tool_kind("execute script") == :execute
      assert Quirks.infer_tool_kind("shell command") == :execute
    end

    test "infers search from search patterns" do
      assert Quirks.infer_tool_kind("search codebase") == :search
      assert Quirks.infer_tool_kind("find references") == :search
      assert Quirks.infer_tool_kind("grep for pattern") == :search
    end

    test "infers think from reasoning patterns" do
      assert Quirks.infer_tool_kind("think about approach") == :think
      assert Quirks.infer_tool_kind("reasoning step") == :think
    end

    test "infers fetch from HTTP patterns" do
      assert Quirks.infer_tool_kind("fetch url") == :fetch
      assert Quirks.infer_tool_kind("http request") == :fetch
    end

    test "returns :other for unrecognized patterns" do
      assert Quirks.infer_tool_kind("do something") == :other
    end

    test "returns :other for nil" do
      assert Quirks.infer_tool_kind(nil) == :other
    end

    test "is case-insensitive" do
      assert Quirks.infer_tool_kind("READ_FILE") == :read
      assert Quirks.infer_tool_kind("Bash Run") == :execute
    end
  end

  describe "startup_timeout/2" do
    test "gemini gets 15s timeout" do
      assert Quirks.startup_timeout("gemini", ["--acp"]) == 15_000
    end

    test "claude gets 15s timeout" do
      assert Quirks.startup_timeout("claude", ["acp"]) == 15_000
    end

    test "copilot gets 20s timeout" do
      assert Quirks.startup_timeout("copilot", ["--acp", "--stdio"]) == 20_000
    end

    test "default gets 10s timeout" do
      assert Quirks.startup_timeout("kimi", ["acp"]) == 10_000
    end
  end

  describe "session_create_timeout/2" do
    test "claude gets 60s session timeout" do
      assert Quirks.session_create_timeout("claude", ["acp"]) == 60_000
    end

    test "default gets 15s session timeout" do
      assert Quirks.session_create_timeout("kimi", ["acp"]) == 15_000
    end
  end

  describe "close_grace_ms/2" do
    test "qoder gets 750ms grace" do
      assert Quirks.close_grace_ms("qodercli", ["--acp"]) == 750
    end

    test "default gets 100ms grace" do
      assert Quirks.close_grace_ms("kimi", ["acp"]) == 100
    end
  end

  describe "should_filter_stdout?/2" do
    test "qoder returns true" do
      assert Quirks.should_filter_stdout?("qodercli", ["--acp"])
    end

    test "other agents return false" do
      refute Quirks.should_filter_stdout?("kimi", ["acp"])
      refute Quirks.should_filter_stdout?("claude", ["acp"])
    end
  end

  describe "filter_non_json_lines/1" do
    test "keeps JSON lines" do
      input = ~s({"jsonrpc":"2.0","id":1}) <> "\n" <> ~s({"method":"test"})
      assert Quirks.filter_non_json_lines(input) == input
    end

    test "removes non-JSON lines" do
      input = "some debug output\n{\"jsonrpc\":\"2.0\"}\nmore debug\n"
      result = Quirks.filter_non_json_lines(input)

      refute String.contains?(result, "some debug output")
      refute String.contains?(result, "more debug")
      assert String.contains?(result, "jsonrpc")
    end

    test "keeps empty lines" do
      input = "\n{\"test\":true}\n"
      result = Quirks.filter_non_json_lines(input)
      assert String.starts_with?(result, "\n")
    end

    test "handles all-non-JSON input" do
      assert Quirks.filter_non_json_lines("hello\nworld\n") == ""
    end
  end

  describe "needs_preflight?/2" do
    test "copilot returns true" do
      assert Quirks.needs_preflight?("copilot", ["--acp", "--stdio"])
    end

    test "other agents return false" do
      refute Quirks.needs_preflight?("kimi", ["acp"])
      refute Quirks.needs_preflight?("claude", ["acp"])
    end
  end

  describe "mutate_args/3" do
    test "non-quirk agents pass through unchanged" do
      {cmd, args} = Quirks.mutate_args("kimi", ["acp"])
      assert {cmd, args} == {"kimi", ["acp"]}
    end

    test "qoder forwards max_turns" do
      {_cmd, args} = Quirks.mutate_args("qodercli", ["--acp"], max_turns: 10)
      assert "--max-turns" in args
      assert "10" in args
    end

    test "qoder forwards allowed_tools" do
      {_cmd, args} = Quirks.mutate_args("qodercli", ["--acp"], allowed_tools: ["read", "write"])
      assert "--allowed-tools" in args
      assert Enum.any?(args, &String.contains?(&1, "read,write"))
    end
  end
end
