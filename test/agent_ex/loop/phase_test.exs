defmodule AgentEx.Loop.PhaseTest do
  use ExUnit.Case, async: true

  alias AgentEx.Loop.Phase
  alias AgentEx.Loop.Context

  describe "initial_phase/1" do
    test ":agentic starts at :execute" do
      assert Phase.initial_phase(:agentic) == :execute
    end

    test ":agentic_planned starts at :plan" do
      assert Phase.initial_phase(:agentic_planned) == :plan
    end

    test ":turn_by_turn starts at :review" do
      assert Phase.initial_phase(:turn_by_turn) == :review
    end

    test ":conversational starts at :execute" do
      assert Phase.initial_phase(:conversational) == :execute
    end
  end

  describe "transition/2 — :agentic" do
    setup do
      ctx = %Context{mode: :agentic, phase: :execute}
      {:ok, ctx: ctx}
    end

    test "execute → execute is valid", %{ctx: ctx} do
      assert {:ok, %Context{phase: :execute}} = Phase.transition(ctx, :execute)
    end

    test "execute → done is valid", %{ctx: ctx} do
      assert {:ok, %Context{phase: :done}} = Phase.transition(ctx, :done)
    end

    test "execute → plan is invalid", %{ctx: ctx} do
      assert {:error, {:invalid_transition, :agentic, :execute, :plan}} =
               Phase.transition(ctx, :plan)
    end

    test "execute → review is invalid", %{ctx: ctx} do
      assert {:error, {:invalid_transition, :agentic, :execute, :review}} =
               Phase.transition(ctx, :review)
    end
  end

  describe "transition/2 — :agentic_planned" do
    setup do
      ctx = %Context{mode: :agentic_planned}
      {:ok, ctx: ctx}
    end

    test "init → plan is valid", %{ctx: ctx} do
      ctx = %{ctx | phase: :init}
      assert {:ok, %Context{phase: :plan}} = Phase.transition(ctx, :plan)
    end

    test "plan → execute is valid", %{ctx: ctx} do
      ctx = %{ctx | phase: :plan}
      assert {:ok, %Context{phase: :execute}} = Phase.transition(ctx, :execute)
    end

    test "execute → execute is valid", %{ctx: ctx} do
      ctx = %{ctx | phase: :execute}
      assert {:ok, %Context{phase: :execute}} = Phase.transition(ctx, :execute)
    end

    test "execute → verify is valid", %{ctx: ctx} do
      ctx = %{ctx | phase: :execute}
      assert {:ok, %Context{phase: :verify}} = Phase.transition(ctx, :verify)
    end

    test "verify → done is valid", %{ctx: ctx} do
      ctx = %{ctx | phase: :verify}
      assert {:ok, %Context{phase: :done}} = Phase.transition(ctx, :done)
    end

    test "plan → done is invalid", %{ctx: ctx} do
      ctx = %{ctx | phase: :plan}
      assert {:error, _} = Phase.transition(ctx, :done)
    end

    test "verify → execute is invalid", %{ctx: ctx} do
      ctx = %{ctx | phase: :verify}
      assert {:error, _} = Phase.transition(ctx, :execute)
    end
  end

  describe "transition/2 — :turn_by_turn" do
    setup do
      ctx = %Context{mode: :turn_by_turn}
      {:ok, ctx: ctx}
    end

    test "init → review is valid", %{ctx: ctx} do
      ctx = %{ctx | phase: :init}
      assert {:ok, %Context{phase: :review}} = Phase.transition(ctx, :review)
    end

    test "review → review is valid", %{ctx: ctx} do
      ctx = %{ctx | phase: :review}
      assert {:ok, %Context{phase: :review}} = Phase.transition(ctx, :review)
    end

    test "review → execute is valid", %{ctx: ctx} do
      ctx = %{ctx | phase: :review}
      assert {:ok, %Context{phase: :execute}} = Phase.transition(ctx, :execute)
    end

    test "execute → review is valid", %{ctx: ctx} do
      ctx = %{ctx | phase: :execute}
      assert {:ok, %Context{phase: :review}} = Phase.transition(ctx, :review)
    end

    test "execute → done is valid", %{ctx: ctx} do
      ctx = %{ctx | phase: :execute}
      assert {:ok, %Context{phase: :done}} = Phase.transition(ctx, :done)
    end
  end

  describe "transition/2 — :conversational" do
    setup do
      ctx = %Context{mode: :conversational, phase: :execute}
      {:ok, ctx: ctx}
    end

    test "execute → done is valid", %{ctx: ctx} do
      assert {:ok, %Context{phase: :done}} = Phase.transition(ctx, :done)
    end

    test "execute → execute is invalid", %{ctx: ctx} do
      assert {:error, _} = Phase.transition(ctx, :execute)
    end
  end

  describe "valid?/2" do
    test "returns true for valid transitions" do
      ctx = %Context{mode: :agentic, phase: :execute}
      assert Phase.valid?(ctx, :done)
    end

    test "returns false for invalid transitions" do
      ctx = %Context{mode: :agentic, phase: :execute}
      refute Phase.valid?(ctx, :plan)
    end
  end

  describe "transition!/2" do
    test "returns updated context on valid transition" do
      ctx = %Context{mode: :agentic, phase: :execute}
      assert %Context{phase: :done} = Phase.transition!(ctx, :done)
    end

    test "raises on invalid transition" do
      ctx = %Context{mode: :agentic, phase: :execute}

      assert_raise RuntimeError, ~r/Invalid phase transition/, fn ->
        Phase.transition!(ctx, :plan)
      end
    end
  end
end
