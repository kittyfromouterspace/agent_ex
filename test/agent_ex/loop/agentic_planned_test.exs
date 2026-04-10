defmodule AgentEx.Loop.AgenticPlannedTest do
  use ExUnit.Case, async: true

  alias AgentEx.Loop.Stages.{PlanBuilder, PlanTracker, ModeRouter, VerifyPhase}

  import AgentEx.TestHelpers

  defp passthrough, do: fn ctx -> {:ok, ctx} end

  describe "plan → execute → verify lifecycle" do
    test "PlanBuilder injects prompt, ModeRouter parses plan and transitions to :execute" do
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
              "verification" => "Code written"
            }
          ]
        })

      reentry = fn ctx -> {:ok, ctx} end

      ctx =
        build_planned_ctx(messages: [%{"role" => "system", "content" => "sys"}])
        |> Map.put(:last_response, %AgentEx.LLM.Response{
          content: [%{type: :text, text: plan_json}],
          stop_reason: :end_turn
        })
        |> Map.put(:reentry_pipeline, reentry)

      assert {:ok, ctx} = ModeRouter.call(ctx, passthrough())
      assert ctx.phase == :execute
      assert ctx.plan != nil
      assert length(ctx.plan.steps) == 2
      assert Enum.all?(ctx.plan.steps, &(&1.status == :pending))
    end

    test "PlanTracker marks steps complete and transitions to :verify" do
      plan = %{
        steps: [
          %{
            index: 0,
            description: "Read files",
            tools: ["read_file"],
            verification: "ok",
            status: :complete
          },
          %{
            index: 1,
            description: "Edit code",
            tools: ["write_file"],
            verification: "ok",
            status: :pending
          }
        ]
      }

      ctx =
        build_ctx(mode: :agentic_planned, phase: :execute, plan: plan)
        |> Map.put(:plan_step_index, 1)
        |> Map.put(:accumulated_text, "Step 2 is complete. Code written.")
        |> Map.put(:pending_tool_calls, [])

      assert {:ok, ctx} = PlanTracker.call(ctx, passthrough())
      assert ctx.phase == :verify
      assert Enum.all?(ctx.plan.steps, &(&1.status == :complete))
    end

    test "VerifyPhase injects verification prompt with plan summary" do
      plan = %{
        steps: [
          %{
            index: 0,
            description: "Read files",
            tools: ["read_file"],
            verification: "ok",
            status: :complete
          },
          %{
            index: 1,
            description: "Edit code",
            tools: ["write_file"],
            verification: "ok",
            status: :complete
          }
        ]
      }

      ctx =
        build_ctx(mode: :agentic_planned, phase: :verify, plan: plan)
        |> Map.put(:accumulated_text, "All done.")

      assert {:ok, ctx} = VerifyPhase.call(ctx, passthrough())
      verify_msg = List.last(ctx.messages)
      assert String.contains?(verify_msg["content"], "Verification phase")
      assert String.contains?(verify_msg["content"], "Read files")
      assert String.contains?(verify_msg["content"], "Edit code")
    end
  end

  describe "plan parsing" do
    test "parses structured JSON plan from LLM output" do
      plan_json =
        Jason.encode!(%{
          "steps" => [
            %{
              "index" => 0,
              "description" => "Step A",
              "tools" => ["bash"],
              "verification" => "ok"
            }
          ]
        })

      reentry = fn ctx -> {:ok, ctx} end

      ctx =
        build_ctx(mode: :agentic_planned, phase: :plan)
        |> Map.put(:last_response, %AgentEx.LLM.Response{
          content: [%{type: :text, text: plan_json}],
          stop_reason: :end_turn
        })
        |> Map.put(:reentry_pipeline, reentry)

      assert {:ok, result} = ModeRouter.call(ctx, passthrough())
      assert result.phase == :execute
      assert length(result.plan.steps) == 1
      assert hd(result.plan.steps).description == "Step A"
    end

    test "falls back to heuristic parsing for non-JSON output" do
      reentry = fn ctx -> {:ok, ctx} end

      ctx =
        build_ctx(mode: :agentic_planned, phase: :plan)
        |> Map.put(:last_response, %AgentEx.LLM.Response{
          content: [
            %{type: :text, text: "Step 1. Read the files\nStep 2. Fix the bug"}
          ],
          stop_reason: :end_turn
        })
        |> Map.put(:reentry_pipeline, reentry)

      assert {:ok, result} = ModeRouter.call(ctx, passthrough())
      assert result.phase == :execute
      assert result.plan != nil
      assert length(result.plan.steps) == 2
    end
  end

  describe "pre-built plan skips :plan phase" do
    test "PlanBuilder passes through when phase is :execute with existing plan" do
      plan = %{
        steps: [
          %{
            index: 0,
            description: "Step 1",
            tools: ["bash"],
            verification: "ok",
            status: :pending
          }
        ]
      }

      ctx = build_ctx(mode: :agentic_planned, phase: :execute, plan: plan)

      assert {:ok, result} = PlanBuilder.call(ctx, passthrough())
      assert result.messages == ctx.messages
    end
  end
end
