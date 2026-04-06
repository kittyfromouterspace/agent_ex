defmodule AgentEx.Loop.Stages.HumanCheckpointTest do
  use ExUnit.Case, async: true

  alias AgentEx.Loop.Stages.HumanCheckpoint

  import AgentEx.TestHelpers

  defp passthrough, do: fn ctx -> {:ok, ctx} end

  describe ":turn_by_turn + :review phase — approval" do
    test "calls on_human_input and transitions to :execute on approval" do
      test_pid = self()

      on_human_input = fn proposal, _ctx ->
        send(test_pid, {:proposal, proposal})
        {:approve, _ctx}
      end

      ctx =
        build_ctx(
          mode: :turn_by_turn,
          phase: :review,
          callbacks: mock_callbacks(%{on_human_input: on_human_input})
        )
        |> Map.put(:accumulated_text, "I will refactor the module.")
        |> Map.put(:pending_tool_calls, [])

      assert {:ok, result} = HumanCheckpoint.call(ctx, passthrough())
      assert result.phase == :execute
      assert_received {:proposal, proposal}
      assert proposal.thinking == "I will refactor the module."
    end

    test "appends approval message to messages" do
      on_human_input = fn _proposal, ctx -> {:approve, ctx} end

      ctx =
        build_ctx(
          mode: :turn_by_turn,
          phase: :review,
          callbacks: mock_callbacks(%{on_human_input: on_human_input})
        )
        |> Map.put(:accumulated_text, "I will fix the bug.")
        |> Map.put(:pending_tool_calls, [])

      assert {:ok, result} = HumanCheckpoint.call(ctx, passthrough())
      last_msg = List.last(result.messages)
      assert String.contains?(last_msg["content"], "Approved")
    end
  end

  describe ":turn_by_turn + :review phase — approval with feedback" do
    test "appends feedback message and transitions to :execute" do
      on_human_input = fn _proposal, ctx -> {:approve, "Use pattern matching", ctx} end

      ctx =
        build_ctx(
          mode: :turn_by_turn,
          phase: :review,
          callbacks: mock_callbacks(%{on_human_input: on_human_input})
        )
        |> Map.put(:accumulated_text, "I will use conditionals.")
        |> Map.put(:pending_tool_calls, [])

      assert {:ok, result} = HumanCheckpoint.call(ctx, passthrough())
      assert result.phase == :execute
      last_msg = List.last(result.messages)
      assert String.contains?(last_msg["content"], "Use pattern matching")
    end
  end

  describe ":turn_by_turn + :review phase — abort" do
    test "returns done with abort reason" do
      on_human_input = fn _proposal, _ctx -> {:abort, "too risky"} end

      ctx =
        build_ctx(
          mode: :turn_by_turn,
          phase: :review,
          callbacks: mock_callbacks(%{on_human_input: on_human_input})
        )
        |> Map.put(:accumulated_text, "I will delete everything.")
        |> Map.put(:pending_tool_calls, [])

      assert {:done, result} = HumanCheckpoint.call(ctx, passthrough())
      assert String.contains?(result.text, "aborted")
      assert String.contains?(result.text, "too risky")
    end
  end

  describe ":turn_by_turn + :review phase — edge cases" do
    test "passes through when no accumulated text" do
      ctx =
        build_ctx(
          mode: :turn_by_turn,
          phase: :review,
          callbacks: mock_callbacks(%{on_human_input: fn _, ctx -> {:approve, ctx} end})
        )
        |> Map.put(:accumulated_text, "")
        |> Map.put(:pending_tool_calls, [])

      assert {:ok, result} = HumanCheckpoint.call(ctx, passthrough())
      assert result.phase == :review
    end

    test "passes through when pending_human_response is true" do
      ctx =
        build_ctx(
          mode: :turn_by_turn,
          phase: :review,
          callbacks: mock_callbacks(%{on_human_input: fn _, ctx -> {:approve, ctx} end})
        )
        |> Map.put(:accumulated_text, "Some text.")
        |> Map.put(:pending_tool_calls, [])
        |> Map.put(:pending_human_response, true)

      assert {:ok, result} = HumanCheckpoint.call(ctx, passthrough())
      assert result.phase == :review
    end
  end

  describe "passthrough" do
    test "passes through when mode is :turn_by_turn and phase is :execute" do
      ctx = build_ctx(mode: :turn_by_turn, phase: :execute)

      assert {:ok, result} = HumanCheckpoint.call(ctx, passthrough())
      assert result == ctx
    end

    test "passes through when mode is :agentic" do
      ctx = build_ctx(mode: :agentic, phase: :execute)

      assert {:ok, result} = HumanCheckpoint.call(ctx, passthrough())
      assert result == ctx
    end

    test "passes through when no on_human_input callback" do
      ctx =
        build_ctx(mode: :turn_by_turn, phase: :review, callbacks: mock_callbacks())
        |> Map.put(:accumulated_text, "Some response.")
        |> Map.put(:pending_tool_calls, [])

      assert {:ok, result} = HumanCheckpoint.call(ctx, passthrough())
      assert result.phase == :execute
    end
  end

  describe "proposal construction" do
    test "includes tool preview from last_response content" do
      test_pid = self()

      on_human_input = fn proposal, _ctx ->
        send(test_pid, {:proposal, proposal})
        {:approve, _ctx}
      end

      ctx =
        build_ctx(
          mode: :turn_by_turn,
          phase: :review,
          callbacks: mock_callbacks(%{on_human_input: on_human_input})
        )
        |> Map.put(:accumulated_text, "Let me check.")
        |> Map.put(:pending_tool_calls, [])
        |> Map.put(:last_response, %{
          "content" => [
            %{"type" => "text", "text" => "Let me check."},
            %{"type" => "tool_use", "id" => "c1", "name" => "read_file", "input" => %{}}
          ]
        })

      HumanCheckpoint.call(ctx, passthrough())

      assert_received {:proposal, proposal}
      assert "read_file" in proposal.tools_needed
    end
  end
end
