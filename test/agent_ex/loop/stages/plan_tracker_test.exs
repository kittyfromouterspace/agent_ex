defmodule AgentEx.Loop.Stages.PlanTrackerTest do
  use ExUnit.Case, async: true

  alias AgentEx.Loop.Stages.PlanTracker

  import AgentEx.TestHelpers

  defp passthrough, do: fn ctx -> {:ok, ctx} end

  defp plan_with_steps(count) do
    steps =
      for i <- 0..(count - 1) do
        %{
          index: i,
          description: "Step #{i + 1}",
          tools: ["read_file"],
          verification: "ok",
          status: :pending
        }
      end

    %{steps: steps}
  end

  describe "step completion detection" do
    test "detects step completion via regex pattern" do
      ctx =
        build_ctx(mode: :agentic_planned, phase: :execute, plan: plan_with_steps(2))
        |> Map.put(:accumulated_text, "Step 1 is complete. Moving on.")
        |> Map.put(:pending_tool_calls, [])

      assert {:ok, result} = PlanTracker.call(ctx, passthrough())
      assert result.plan_step_index == 1
      assert hd(result.plan.steps).status == :complete
    end

    test "detects step completion via alternative pattern" do
      ctx =
        build_ctx(mode: :agentic_planned, phase: :execute, plan: plan_with_steps(2))
        |> Map.put(:accumulated_text, "Completed step 1 successfully.")
        |> Map.put(:pending_tool_calls, [])

      assert {:ok, result} = PlanTracker.call(ctx, passthrough())
      assert result.plan_step_index == 1
    end

    test "detects step completion via checkmark pattern" do
      ctx =
        build_ctx(mode: :agentic_planned, phase: :execute, plan: plan_with_steps(2))
        |> Map.put(:accumulated_text, "✓ Step 1 done")
        |> Map.put(:pending_tool_calls, [])

      assert {:ok, result} = PlanTracker.call(ctx, passthrough())
      assert result.plan_step_index == 1
    end
  end

  describe "step in progress" do
    test "marks step as in_progress when not complete" do
      ctx =
        build_ctx(mode: :agentic_planned, phase: :execute, plan: plan_with_steps(2))
        |> Map.put(:accumulated_text, "Working on reading files...")
        |> Map.put(:pending_tool_calls, [])

      assert {:ok, result} = PlanTracker.call(ctx, passthrough())
      assert result.plan_step_index == 0
      assert hd(result.plan.steps).status == :in_progress
    end

    test "does not advance step when tool calls are pending" do
      ctx =
        build_ctx(mode: :agentic_planned, phase: :execute, plan: plan_with_steps(2))
        |> Map.put(:accumulated_text, "Step 1 is complete")
        |> Map.put(:pending_tool_calls, [%{"name" => "read_file"}])

      assert {:ok, result} = PlanTracker.call(ctx, passthrough())
      assert result.plan_step_index == 0
    end
  end

  describe "transition to :verify" do
    test "transitions to verify when all steps complete" do
      plan = %{
        steps: [
          %{index: 0, description: "Step 1", tools: [], verification: "ok", status: :complete},
          %{index: 1, description: "Step 2", tools: [], verification: "ok", status: :pending}
        ]
      }

      ctx =
        build_ctx(mode: :agentic_planned, phase: :execute, plan: plan)
        |> Map.put(:plan_step_index, 1)
        |> Map.put(:accumulated_text, "Step 2 is complete")
        |> Map.put(:pending_tool_calls, [])

      assert {:ok, result} = PlanTracker.call(ctx, passthrough())
      assert result.phase == :verify
    end

    test "does not transition to verify when steps remain" do
      plan = %{
        steps: [
          %{index: 0, description: "Step 1", tools: [], verification: "ok", status: :pending},
          %{index: 1, description: "Step 2", tools: [], verification: "ok", status: :pending}
        ]
      }

      ctx =
        build_ctx(mode: :agentic_planned, phase: :execute, plan: plan)
        |> Map.put(:accumulated_text, "Step 1 is complete")
        |> Map.put(:pending_tool_calls, [])

      assert {:ok, result} = PlanTracker.call(ctx, passthrough())
      assert result.phase == :execute
    end
  end

  describe "progress injection" do
    test "injects progress message after step completion" do
      ctx =
        build_ctx(mode: :agentic_planned, phase: :execute, plan: plan_with_steps(3))
        |> Map.put(:accumulated_text, "Step 1 is complete")
        |> Map.put(:pending_tool_calls, [])

      assert {:ok, result} = PlanTracker.call(ctx, passthrough())

      progress_msg = List.last(result.messages)
      assert progress_msg["role"] == "user"
      assert String.contains?(progress_msg["content"], "Plan progress")
      assert String.contains?(progress_msg["content"], "1/3")
    end
  end

  describe "on_step_complete callback" do
    test "invokes callback when a step completes" do
      test_pid = self()

      on_step_complete = fn step, _result, _ctx ->
        send(test_pid, {:step_complete, step})
      end

      ctx =
        build_ctx(
          mode: :agentic_planned,
          phase: :execute,
          plan: plan_with_steps(2),
          callbacks: mock_callbacks(%{on_step_complete: on_step_complete})
        )
        |> Map.put(:accumulated_text, "Step 1 is complete")
        |> Map.put(:pending_tool_calls, [])

      PlanTracker.call(ctx, passthrough())

      assert_received {:step_complete, step}
      assert step.description == "Step 1"
    end
  end

  describe "passthrough" do
    test "passes through when mode is not :agentic_planned" do
      ctx = build_ctx(mode: :agentic, phase: :execute)

      assert {:ok, result} = PlanTracker.call(ctx, passthrough())
      assert result == ctx
    end

    test "passes through when plan is nil" do
      ctx =
        build_ctx(mode: :agentic_planned, phase: :execute, plan: nil)
        |> Map.put(:accumulated_text, "some text")

      assert {:ok, result} = PlanTracker.call(ctx, passthrough())
      assert result == ctx
    end

    test "passes through when phase is not :execute" do
      ctx = build_ctx(mode: :agentic_planned, phase: :plan, plan: plan_with_steps(2))

      assert {:ok, result} = PlanTracker.call(ctx, passthrough())
      assert result == ctx
    end
  end
end
