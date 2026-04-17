defmodule Agentic.Loop.TurnByTurnTest do
  use ExUnit.Case, async: true

  alias Agentic.Loop.Stages.{HumanCheckpoint, ModeRouter}

  import Agentic.TestHelpers

  defp passthrough, do: fn ctx -> {:ok, ctx} end

  describe "human approval flow" do
    test "approves proposal and transitions to :execute" do
      test_pid = self()

      on_human_input = fn proposal, ctx ->
        send(test_pid, {:proposal, proposal})
        {:approve, ctx}
      end

      ctx =
        build_ctx(
          mode: :turn_by_turn,
          phase: :review,
          callbacks: mock_callbacks(%{on_human_input: on_human_input})
        )
        |> Map.put(:accumulated_text, "I will check the file.")
        |> Map.put(:pending_tool_calls, [])

      assert {:ok, result} = HumanCheckpoint.call(ctx, passthrough())
      assert result.phase == :execute
      assert_received {:proposal, proposal}
      assert proposal.thinking == "I will check the file."
    end
  end

  describe "human revision flow" do
    test "approves with feedback and appends to messages" do
      on_human_input = fn _proposal, ctx ->
        {:approve, "Use pattern matching instead", ctx}
      end

      ctx =
        build_ctx(
          mode: :turn_by_turn,
          phase: :review,
          callbacks: mock_callbacks(%{on_human_input: on_human_input})
        )
        |> Map.put(:accumulated_text, "I'll use conditionals.")
        |> Map.put(:pending_tool_calls, [])

      assert {:ok, result} = HumanCheckpoint.call(ctx, passthrough())
      assert result.phase == :execute
      last_msg = List.last(result.messages)
      assert String.contains?(last_msg["content"], "pattern matching")
    end
  end

  describe "abort flow" do
    test "returns partial results on abort" do
      on_human_input = fn _proposal, _ctx ->
        {:abort, "user cancelled"}
      end

      ctx =
        build_ctx(
          mode: :turn_by_turn,
          phase: :review,
          callbacks: mock_callbacks(%{on_human_input: on_human_input})
        )
        |> Map.put(:accumulated_text, "About to delete files.")
        |> Map.put(:pending_tool_calls, [])

      assert {:done, result} = HumanCheckpoint.call(ctx, passthrough())
      assert String.contains?(result.text, "aborted")
      assert String.contains?(result.text, "user cancelled")
    end
  end

  describe "review → execute → review cycling" do
    test "ModeRouter transitions from :execute to :review on end_turn" do
      reentry = fn ctx -> {:ok, ctx} end

      ctx =
        build_ctx(mode: :turn_by_turn, phase: :execute)
        |> Map.put(:last_response, %Agentic.LLM.Response{
          content: [%{type: :text, text: "Done with tools."}],
          stop_reason: :end_turn
        })
        |> Map.put(:reentry_pipeline, reentry)

      assert {:ok, result} = ModeRouter.call(ctx, passthrough())
      assert result.phase == :review
    end

    test "ModeRouter passes tool_use through for execution" do
      ctx =
        build_ctx(mode: :turn_by_turn, phase: :review)
        |> Map.put(:last_response, %Agentic.LLM.Response{
          content: [
            %{type: :text, text: "Let me check."},
            %{
              type: :tool_use,
              id: "c1",
              name: "read_file",
              input: %{"path" => "a.txt"}
            }
          ],
          stop_reason: :tool_use
        })
        |> Map.put(:turns_used, 1)

      assert {:ok, result} = ModeRouter.call(ctx, passthrough())
      assert length(result.pending_tool_calls) == 1
    end
  end

  describe "multiple chunks with review→execute→review cycling" do
    test "review end_turn stops the loop, execute end_turn transitions to review" do
      ctx_review =
        build_ctx(mode: :turn_by_turn, phase: :review)
        |> Map.put(:last_response, %Agentic.LLM.Response{
          content: [%{type: :text, text: "First chunk."}],
          stop_reason: :end_turn
        })

      assert {:done, result} = ModeRouter.call(ctx_review, passthrough())
      assert result.text == "First chunk."

      reentry = fn ctx -> {:ok, ctx} end

      ctx_execute =
        build_ctx(mode: :turn_by_turn, phase: :execute)
        |> Map.put(:last_response, %Agentic.LLM.Response{
          content: [%{type: :text, text: "Done executing."}],
          stop_reason: :end_turn
        })
        |> Map.put(:reentry_pipeline, reentry)

      assert {:ok, r2} = ModeRouter.call(ctx_execute, passthrough())
      assert r2.phase == :review
    end
  end
end
