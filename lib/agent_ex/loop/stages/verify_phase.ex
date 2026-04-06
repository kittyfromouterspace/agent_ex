defmodule AgentEx.Loop.Stages.VerifyPhase do
  @moduledoc """
  Post-execution verification stage for :agentic_planned mode.

  Only active when `ctx.mode == :agentic_planned` and `ctx.phase == :verify`.
  Injected before LLMCall in the pipeline.

  Injects a verification prompt that asks the LLM to review the original plan
  against what was actually done and report any issues.
  """

  @behaviour AgentEx.Loop.Stage

  alias AgentEx.Loop.Context

  @impl true
  def call(%Context{mode: :agentic_planned, phase: :verify} = ctx, next) do
    verification_msg = build_verification_prompt(ctx)

    %{ctx | messages: ctx.messages ++ [verification_msg]}
    |> next.()
  end

  @impl true
  def call(ctx, next), do: next.(ctx)

  defp build_verification_prompt(ctx) do
    plan_summary = format_plan_summary(ctx.plan)
    actions_summary = format_actions_summary(ctx)

    %{
      "role" => "user",
      "content" =>
        "[System: Verification phase]\n\n" <>
          "Here was the original plan:\n#{plan_summary}\n\n" <>
          "Here is what was done:\n#{actions_summary}\n\n" <>
          "Verify each step was completed correctly. Report any issues or incomplete work. " <>
          "Provide a concise summary of the final outcome."
    }
  end

  defp format_plan_summary(nil), do: "(No plan available)"

  defp format_plan_summary(plan) do
    steps = plan[:steps] || []

    steps
    |> Enum.with_index(1)
    |> Enum.map(fn {step, num} ->
      status = step[:status] || "unknown"
      "#{num}. [#{status}] #{step[:description]}"
    end)
    |> Enum.join("\n")
  end

  defp format_actions_summary(ctx) do
    text = ctx.accumulated_text

    if text != "" do
      String.slice(text, 0, 2000)
    else
      "(No accumulated output)"
    end
  end
end
