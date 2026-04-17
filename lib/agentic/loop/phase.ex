defmodule Agentic.Loop.Phase do
  @moduledoc """
  Phase state machine with per-mode validated transitions.

  All phase transitions in stages go through `transition/2` — never direct
  `ctx.phase` mutation. This gives compile-time safety via `transition!/2` in
  hot paths and `{:error, _}` returns for graceful handling elsewhere.

  No external dependencies — plain data + pattern matching.
  """

  @phases [:init, :plan, :execute, :review, :verify, :done]

  @mode_transitions %{
    agentic: %{
      init: [:execute],
      execute: [:execute, :done],
      done: []
    },
    agentic_planned: %{
      init: [:plan],
      plan: [:execute],
      execute: [:execute, :verify],
      verify: [:done],
      done: []
    },
    turn_by_turn: %{
      init: [:review],
      review: [:review, :execute],
      execute: [:review, :done],
      done: []
    },
    conversational: %{
      init: [:execute],
      execute: [:done],
      done: []
    }
  }

  @type phase :: :init | :plan | :execute | :review | :verify | :done
  @type mode :: :agentic | :agentic_planned | :turn_by_turn | :conversational

  def phases, do: @phases
  def mode_transitions, do: @mode_transitions

  @doc """
  Attempt a phase transition. Returns `{:ok, updated_context}` or `{:error, {:invalid_transition, mode, from, to}}`.
  """
  def transition(ctx, next_phase) do
    transitions = Map.get(@mode_transitions, ctx.mode, %{})
    allowed = Map.get(transitions, ctx.phase, [])

    if next_phase in allowed do
      Agentic.Telemetry.event([:phase, :transition], %{}, %{
        session_id: ctx.session_id,
        mode: ctx.mode,
        from: ctx.phase,
        to: next_phase
      })

      {:ok, %{ctx | phase: next_phase}}
    else
      {:error, {:invalid_transition, ctx.mode, ctx.phase, next_phase}}
    end
  end

  @doc """
  Same as `transition/2` but raises on invalid transition.
  """
  def transition!(ctx, next_phase) do
    case transition(ctx, next_phase) do
      {:ok, ctx} -> ctx
      {:error, reason} -> raise "Invalid phase transition: #{inspect(reason)}"
    end
  end

  @doc """
  Check if a transition is valid without performing it.
  """
  def valid?(ctx, next_phase) do
    transitions = Map.get(@mode_transitions, ctx.mode, %{})
    next_phase in Map.get(transitions, ctx.phase, [])
  end

  @doc """
  Return the initial phase for a given mode.
  """
  @spec initial_phase(mode()) :: phase()
  def initial_phase(:agentic), do: :execute
  def initial_phase(:agentic_planned), do: :plan
  def initial_phase(:turn_by_turn), do: :review
  def initial_phase(:conversational), do: :execute
end
