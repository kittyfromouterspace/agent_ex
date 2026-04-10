defmodule AgentEx.Loop.Stages.PlanBuilderTest do
  use ExUnit.Case, async: true

  alias AgentEx.Loop.Stages.PlanBuilder

  import AgentEx.TestHelpers

  defp passthrough, do: fn ctx -> {:ok, ctx} end

  describe "agentic_planned + :plan phase — prompt injection" do
    test "injects plan prompt when no user message with 'steps' exists" do
      ctx =
        build_planned_ctx(messages: [%{"role" => "system", "content" => "You are helpful."}])

      assert {:ok, result} = PlanBuilder.call(ctx, passthrough())
      assert length(result.messages) == 2

      last_msg = List.last(result.messages)
      assert last_msg["role"] == "user"
      assert String.contains?(last_msg["content"], "steps")
      assert String.contains?(last_msg["content"], "JSON")
    end

    test "injects prompt when messages contain only system message" do
      ctx = build_planned_ctx(messages: [%{"role" => "system", "content" => "sys"}])

      assert {:ok, result} = PlanBuilder.call(ctx, passthrough())
      assert length(result.messages) == 2
    end

    test "injects prompt when last user message has list content blocks without 'steps'" do
      ctx =
        build_planned_ctx(
          messages: [
            %{"role" => "system", "content" => "sys"},
            %{"role" => "user", "content" => [%{type: :text, text: "Fix the bug"}]}
          ]
        )

      assert {:ok, result} = PlanBuilder.call(ctx, passthrough())
      assert length(result.messages) == 3

      last_msg = List.last(result.messages)
      assert String.contains?(last_msg["content"], "steps")
    end
  end

  describe "agentic_planned + :plan phase — revision pass-through" do
    test "does not inject prompt when last user message already contains 'steps'" do
      ctx =
        build_planned_ctx(
          messages: [
            %{"role" => "system", "content" => "sys"},
            %{"role" => "user", "content" => "Break this into steps for me"}
          ]
        )

      assert {:ok, result} = PlanBuilder.call(ctx, passthrough())
      assert length(result.messages) == 2
    end
  end

  describe "passthrough — wrong mode or phase" do
    test "passes through when mode is :agentic" do
      ctx = build_ctx(mode: :agentic, phase: :execute)
      assert {:ok, result} = PlanBuilder.call(ctx, passthrough())
      assert result.messages == ctx.messages
    end

    test "passes through when mode is :agentic_planned but phase is :execute" do
      ctx = build_ctx(mode: :agentic_planned, phase: :execute)
      assert {:ok, result} = PlanBuilder.call(ctx, passthrough())
      assert result.messages == ctx.messages
    end

    test "passes through when mode is :conversational" do
      ctx = build_ctx(mode: :conversational, phase: :execute)
      assert {:ok, result} = PlanBuilder.call(ctx, passthrough())
      assert result.messages == ctx.messages
    end
  end
end
