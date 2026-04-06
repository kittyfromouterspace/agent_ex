defmodule AgentEx.Loop.ContextCompressionTest do
  use ExUnit.Case, async: true

  alias AgentEx.Loop.ContextCompression

  import AgentEx.TestHelpers

  describe "estimate_tokens/1" do
    test "returns reasonable estimates" do
      messages = [%{"role" => "user", "content" => "Hello world"}]
      tokens = ContextCompression.estimate_tokens(messages)
      assert tokens > 0
      assert tokens < 100
    end

    test "handles list content blocks" do
      messages = [
        %{
          "role" => "assistant",
          "content" => [%{"type" => "text", "text" => "Response text here"}]
        }
      ]

      tokens = ContextCompression.estimate_tokens(messages)
      assert tokens > 0
    end

    test "handles empty messages" do
      assert ContextCompression.estimate_tokens([]) == 0
    end
  end

  describe "compress/3 — under budget" do
    test "returns messages unchanged when under budget" do
      messages = [
        %{"role" => "system", "content" => "You are helpful."},
        %{"role" => "user", "content" => "Hello"}
      ]

      ctx = build_ctx()
      {result, was_summarized} = ContextCompression.compress(messages, 10_000, ctx)
      assert result == messages
      refute was_summarized
    end
  end

  describe "compress/3 — truncation" do
    test "truncates older messages when over budget" do
      messages =
        for _ <- 1..20 do
          %{"role" => "user", "content" => String.duplicate("x", 500)}
        end

      ctx = build_ctx()
      {result, was_summarized} = ContextCompression.compress(messages, 500, ctx)
      refute was_summarized
      assert length(result) < length(messages)
    end
  end

  describe "compress/3 — LLM summarization fallback" do
    test "falls back to truncation when LLM error" do
      messages =
        for _ <- 1..50 do
          %{"role" => "user", "content" => String.duplicate("z", 500)}
        end

      llm_chat = fn _params -> {:error, :rate_limited} end

      ctx = build_ctx(callbacks: %{llm_chat: llm_chat})
      {result, was_summarized} = ContextCompression.compress(messages, 500, ctx)
      refute was_summarized
      assert length(result) < length(messages)
    end
  end

  describe "truncate/2" do
    test "preserves system messages" do
      messages = [
        %{"role" => "system", "content" => "You are helpful."},
        %{"role" => "user", "content" => String.duplicate("a", 5000)},
        %{"role" => "user", "content" => "short"}
      ]

      result = ContextCompression.truncate(messages, 100)
      system_msgs = Enum.filter(result, &(&1["role"] == "system"))
      assert length(system_msgs) == 1
    end

    test "keeps most recent messages" do
      long = String.duplicate("x", 500)

      messages = [
        %{"role" => "user", "content" => long},
        %{"role" => "user", "content" => long},
        %{"role" => "user", "content" => "recent important"}
      ]

      result = ContextCompression.truncate(messages, 200)
      last = List.last(result)
      assert last["content"] == "recent important"
    end
  end
end
