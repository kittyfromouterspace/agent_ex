defmodule AgentEx.Loop.Stages.HumanCheckpoint do
  @moduledoc """
  Human-in-the-loop yield stage for :turn_by_turn mode.

  Only active when `ctx.mode == :turn_by_turn`. Sits after ModeRouter in the pipeline.

  When `ctx.phase == :review` and the agent produced text (not tool calls):
  builds a proposal map from the response and calls the `:on_human_input` callback.

  The callback returns:
  - `{:approve, ctx}` — proceed as proposed
  - `{:approve, feedback, ctx}` — proceed but incorporate feedback
  - `{:abort, reason}` — stop the loop, return partial results

  When `ctx.phase == :execute` — pass through (tools should execute normally).
  """

  @behaviour AgentEx.Loop.Stage

  alias AgentEx.Loop.Context
  alias AgentEx.Loop.Phase

  require Logger

  @impl true
  def call(%Context{mode: :turn_by_turn, phase: :review, pending_tool_calls: []} = ctx, next) do
    text = ctx.accumulated_text

    if text != "" and not ctx.pending_human_response do
      proposal = build_proposal(ctx)
      handle_human_response(ctx, next, proposal)
    else
      next.(ctx)
    end
  end

  @impl true
  def call(%Context{mode: :turn_by_turn, phase: :execute} = ctx, next) do
    next.(ctx)
  end

  @impl true
  def call(ctx, next), do: next.(ctx)

  defp build_proposal(ctx) do
    text = ctx.accumulated_text

    tool_preview =
      case ctx.last_response do
        %{"content" => content} when is_list(content) ->
          content
          |> Enum.filter(&(&1["type"] == "tool_use"))
          |> Enum.map(&(&1["name"] || "unknown"))

        _ ->
          []
      end

    %{
      thinking: text,
      proposed_action: extract_proposed_action(text),
      tools_needed: tool_preview,
      risks: [],
      confidence: nil,
      can_proceed_independently: true
    }
  end

  defp extract_proposed_action(text) do
    text
    |> String.split("\n")
    |> Enum.take(3)
    |> Enum.join(" ")
    |> String.slice(0, 300)
  end

  defp handle_human_response(ctx, next, proposal) do
    case get_human_input(ctx, proposal) do
      {:approve, ctx} ->
        ctx = Phase.transition!(ctx, :execute)
        ctx = append_human_message(ctx, "Approved. Proceed.")
        reentry_or_next(ctx, next)

      {:approve, feedback, ctx} ->
        ctx = Phase.transition!(ctx, :execute)
        ctx = append_human_message(ctx, "Approved with feedback: #{feedback}")
        reentry_or_next(ctx, next)

      {:abort, reason} ->
        Logger.info("HumanCheckpoint: aborted by human — #{reason}")

        {:done,
         %{
           text: ctx.accumulated_text <> "\n\n[Session aborted: #{reason}]",
           cost: ctx.total_cost,
           tokens: ctx.total_tokens,
           steps: ctx.turns_used
         }}
    end
  end

  defp get_human_input(ctx, proposal) do
    case ctx.callbacks[:on_human_input] do
      nil ->
        {:approve, ctx}

      cb when is_function(cb, 2) ->
        cb.(proposal, ctx)

      _ ->
        {:approve, ctx}
    end
  end

  defp append_human_message(ctx, text) do
    msg = %{"role" => "user", "content" => text}
    %{ctx | messages: ctx.messages ++ [msg]}
  end

  defp reentry_or_next(ctx, next) do
    if ctx.reentry_pipeline do
      ctx.reentry_pipeline.(ctx)
    else
      next.(ctx)
    end
  end
end
