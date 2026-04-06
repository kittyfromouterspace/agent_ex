defmodule AgentEx.Loop.Stages.VerifyPhaseTest do
  use ExUnit.Case, async: true

  alias AgentEx.Loop.Stages.VerifyPhase

  import AgentEx.TestHelpers

  defp passthrough, do: fn ctx -> {:ok, ctx} end

  describe ":agentic_planned + :verify phase" do
    test "injects verification prompt into messages" do
      plan = %{
        steps: [
          %{
            index: 0,
            description: "Read files",
            tools: ["read_file"],
            verification: "Files read",
            status: :complete
          },
          %{
            index: 1,
            description: "Edit code",
            tools: ["write_file"],
            verification: "Compiles",
            status: :complete
          }
        ]
      }

      ctx =
        build_ctx(mode: :agentic_planned, phase: :verify, plan: plan)
        |> Map.put(:accumulated_text, "I read the files and edited the code.")

      assert {:ok, result} = VerifyPhase.call(ctx, passthrough())

      verify_msg = List.last(result.messages)
      assert verify_msg["role"] == "user"
      assert String.contains?(verify_msg["content"], "Verification phase")
      assert String.contains?(verify_msg["content"], "Read files")
      assert String.contains?(verify_msg["content"], "Edit code")
      assert String.contains?(verify_msg["content"], "edited the code")
    end

    test "includes plan summary with step statuses" do
      plan = %{
        steps: [
          %{index: 0, description: "Step 1", status: :complete},
          %{index: 1, description: "Step 2", status: :failed}
        ]
      }

      ctx =
        build_ctx(mode: :agentic_planned, phase: :verify, plan: plan)
        |> Map.put(:accumulated_text, "Done.")

      assert {:ok, result} = VerifyPhase.call(ctx, passthrough())
      verify_msg = List.last(result.messages)
      assert String.contains?(verify_msg["content"], "complete")
      assert String.contains?(verify_msg["content"], "failed")
    end

    test "handles nil plan gracefully" do
      ctx =
        build_ctx(mode: :agentic_planned, phase: :verify, plan: nil)
        |> Map.put(:accumulated_text, "Something happened.")

      assert {:ok, result} = VerifyPhase.call(ctx, passthrough())
      verify_msg = List.last(result.messages)
      assert String.contains?(verify_msg["content"], "No plan available")
    end

    test "handles empty accumulated_text" do
      ctx =
        build_ctx(mode: :agentic_planned, phase: :verify, plan: nil)
        |> Map.put(:accumulated_text, "")

      assert {:ok, result} = VerifyPhase.call(ctx, passthrough())
      verify_msg = List.last(result.messages)
      assert String.contains?(verify_msg["content"], "No accumulated output")
    end
  end

  describe "passthrough" do
    test "passes through when phase is not :verify" do
      ctx = build_ctx(mode: :agentic_planned, phase: :execute)

      assert {:ok, result} = VerifyPhase.call(ctx, passthrough())
      assert result.messages == ctx.messages
    end

    test "passes through when mode is :agentic" do
      ctx = build_ctx(mode: :agentic, phase: :execute)

      assert {:ok, result} = VerifyPhase.call(ctx, passthrough())
      assert result.messages == ctx.messages
    end

    test "passes through when mode is :conversational" do
      ctx = build_ctx(mode: :conversational, phase: :execute)

      assert {:ok, result} = VerifyPhase.call(ctx, passthrough())
      assert result.messages == ctx.messages
    end
  end
end
