defmodule AgentEx.Loop.Stages.PlanBuilder do
  @moduledoc """
  Injects a structured plan-request prompt for :agentic_planned mode.

  Only active when `ctx.mode == :agentic_planned` and `ctx.phase == :plan`.
  Injected before LLMCall in the pipeline. On first call, it appends a user
  message requesting structured plan output. On subsequent calls (after
  revision), the feedback is already in messages so it passes through.

  This is a thin prompt-engineering stage — it does not call `next` itself.
  It modifies messages and lets LLMCall follow in the pipeline.
  """

  @behaviour AgentEx.Loop.Stage

  alias AgentEx.Loop.Context
  alias AgentEx.Loop.Helpers

  @plan_prompt """
  Break this task into a numbered list of concrete steps. For each step, describe:
  - What to do
  - Which tools you'll use
  - How to verify it worked

  Output the plan as JSON matching this schema:
  {"steps": [{"index": int, "description": str, "tools": [str], "verification": str}]}

  Output ONLY the plan JSON. Do not start execution.
  """

  @impl true
  def call(%Context{mode: :agentic_planned, phase: :plan} = ctx, next) do
    ctx =
      if plan_prompt_needed?(ctx) do
        inject_plan_prompt(ctx)
      else
        ctx
      end

    next.(ctx)
  end

  @impl true
  def call(ctx, next), do: next.(ctx)

  defp plan_prompt_needed?(ctx) do
    messages = ctx.messages
    last_user_msg = find_last_user_message(messages)
    last_user_msg == nil or not String.contains?(last_user_msg, "steps")
  end

  defp find_last_user_message(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(fn msg ->
      if msg["role"] == "user" do
        Helpers.extract_text(msg["content"])
      end
    end)
  end

  defp inject_plan_prompt(ctx) do
    plan_msg = %{
      "role" => "user",
      "content" => @plan_prompt
    }

    %{ctx | messages: ctx.messages ++ [plan_msg]}
  end
end
