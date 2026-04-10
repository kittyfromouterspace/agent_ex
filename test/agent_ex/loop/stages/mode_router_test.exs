defmodule AgentEx.Loop.Stages.ModeRouterTest do
  use ExUnit.Case, async: true

  alias AgentEx.Loop.Stages.ModeRouter

  import AgentEx.TestHelpers

  defp passthrough, do: fn ctx -> {:ok, ctx} end

  describe ":agentic mode — end_turn" do
    test "extracts text and passes to next stage" do
      ctx =
        build_ctx()
        |> Map.put(:last_response, %AgentEx.LLM.Response{
          content: [%{type: :text, text: "Here is the answer."}],
          stop_reason: :end_turn
        })
        |> Map.put(:turns_used, 1)

      assert {:ok, result_ctx} = ModeRouter.call(ctx, passthrough())
      assert result_ctx.accumulated_text == "Here is the answer."
    end

    test "summary nudge fires when no text after tools" do
      reentry_called = :counters.new(1, [:atomics])

      reentry = fn ctx ->
        :counters.add(reentry_called, 1, 1)
        {:ok, ctx}
      end

      ctx =
        build_ctx()
        |> Map.put(:last_response, %AgentEx.LLM.Response{
          content: [%{type: :text, text: ""}],
          stop_reason: :end_turn
        })
        |> Map.put(:turns_used, 1)
        |> Map.put(:accumulated_text, "")
        |> Map.put(:reentry_pipeline, reentry)

      assert {:ok, result_ctx} = ModeRouter.call(ctx, passthrough())
      assert result_ctx.summary_nudge_sent == true
      assert :counters.get(reentry_called, 1) == 1
    end
  end

  describe ":agentic mode — tool_use" do
    test "stores pending_tool_calls" do
      ctx =
        build_ctx()
        |> Map.put(:last_response, %AgentEx.LLM.Response{
          content: [
            %{type: :text, text: "Let me read that."},
            %{
              type: :tool_use,
              id: "call_1",
              name: "read_file",
              input: %{"path" => "test.txt"}
            }
          ],
          stop_reason: :tool_use
        })
        |> Map.put(:turns_used, 1)

      assert {:ok, result_ctx} = ModeRouter.call(ctx, passthrough())
      assert length(result_ctx.pending_tool_calls) == 1
      assert hd(result_ctx.pending_tool_calls).name == "read_file"
    end
  end

  describe "max_tokens" do
    test "returns done with accumulated text" do
      ctx =
        build_ctx()
        |> Map.put(:last_response, %AgentEx.LLM.Response{
          content: [%{type: :text, text: "Partial response..."}],
          stop_reason: :max_tokens
        })
        |> Map.put(:turns_used, 1)

      assert {:done, result} = ModeRouter.call(ctx, passthrough())
      assert result.text == "Partial response..."
    end
  end

  describe "max_turns safety rail" do
    test "fires when turns_used >= max_turns" do
      ctx =
        build_ctx()
        |> Map.put(:last_response, %AgentEx.LLM.Response{
          content: [
            %{type: :text, text: "More work to do."},
            %{
              type: :tool_use,
              id: "call_1",
              name: "bash",
              input: %{"command" => "ls"}
            }
          ],
          stop_reason: :tool_use
        })
        |> Map.put(:turns_used, 50)
        |> Map.put(:config, %{max_turns: 50, telemetry_prefix: [:agent_ex]})

      assert {:done, result} = ModeRouter.call(ctx, passthrough())
      assert result.steps == 50
    end
  end

  describe ":agentic_planned mode — :plan phase" do
    test "parses JSON plan from response and transitions to :execute" do
      reentry = fn ctx -> {:ok, ctx} end

      plan_json =
        Jason.encode!(%{
          "steps" => [
            %{
              "index" => 0,
              "description" => "Read files",
              "tools" => ["read_file"],
              "verification" => "Files read"
            },
            %{
              "index" => 1,
              "description" => "Edit code",
              "tools" => ["write_file"],
              "verification" => "Code compiles"
            }
          ]
        })

      ctx =
        build_ctx(mode: :agentic_planned, phase: :plan)
        |> Map.put(:last_response, %AgentEx.LLM.Response{
          content: [%{type: :text, text: plan_json}],
          stop_reason: :end_turn
        })
        |> Map.put(:reentry_pipeline, reentry)

      assert {:ok, result_ctx} = ModeRouter.call(ctx, passthrough())
      assert result_ctx.phase == :execute
      assert result_ctx.plan != nil
      assert length(result_ctx.plan.steps) == 2
    end
  end

  describe ":agentic_planned mode — :verify phase" do
    test "returns done with verification result" do
      ctx =
        build_ctx(mode: :agentic_planned, phase: :verify)
        |> Map.put(:last_response, %AgentEx.LLM.Response{
          content: [%{type: :text, text: "All steps verified."}],
          stop_reason: :end_turn
        })

      assert {:done, result} = ModeRouter.call(ctx, passthrough())
      assert result.text == "All steps verified."
    end
  end

  describe ":turn_by_turn mode — :review phase" do
    test "accumulates text and passes to next (HumanCheckpoint)" do
      ctx =
        build_ctx(mode: :turn_by_turn, phase: :review)
        |> Map.put(:last_response, %AgentEx.LLM.Response{
          content: [%{type: :text, text: "I'll refactor the module."}],
          stop_reason: :end_turn
        })

      assert {:ok, result_ctx} = ModeRouter.call(ctx, passthrough())
      assert result_ctx.accumulated_text == "I'll refactor the module."
    end
  end

  describe ":turn_by_turn mode — :execute phase, end_turn" do
    test "transitions to :review phase" do
      reentry = fn ctx -> {:ok, ctx} end

      ctx =
        build_ctx(mode: :turn_by_turn, phase: :execute)
        |> Map.put(:last_response, %AgentEx.LLM.Response{
          content: [%{type: :text, text: "Done with tools."}],
          stop_reason: :end_turn
        })
        |> Map.put(:reentry_pipeline, reentry)

      assert {:ok, result_ctx} = ModeRouter.call(ctx, passthrough())
      assert result_ctx.phase == :review
    end
  end

  describe ":conversational mode" do
    test "returns done with accumulated text" do
      ctx =
        build_ctx(mode: :conversational, phase: :execute)
        |> Map.put(:last_response, %AgentEx.LLM.Response{
          content: [%{type: :text, text: "Hello!"}],
          stop_reason: :end_turn
        })

      assert {:done, result} = ModeRouter.call(ctx, passthrough())
      assert result.text == "Hello!"
    end
  end

  describe "unknown stop reason" do
    test "treats as end_turn and returns done" do
      ctx =
        build_ctx()
        |> Map.put(:last_response, %AgentEx.LLM.Response{
          content: [%{type: :text, text: "Something happened."}],
          stop_reason: :unknown_reason
        })

      assert {:done, result} = ModeRouter.call(ctx, passthrough())
      assert result.text == "Something happened."
    end
  end
end
