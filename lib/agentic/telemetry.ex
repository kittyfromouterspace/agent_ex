defmodule Agentic.Telemetry do
  @moduledoc """
  Centralized telemetry helpers for Agentic.

  All telemetry in Agentic goes through this module so event names,
  measurements, and metadata are consistent. The canonical prefix is
  `[:agentic]`.

  ## Event Catalogue

  | Event | Measurements | Metadata |
  |-------|-------------|----------|
  | `[:agentic, :session, :start]` | — | session_id, mode, profile |
  | `[:agentic, :session, :stop]` | duration, cost, tokens, steps | session_id, mode |
  | `[:agentic, :session, :error]` | duration | session_id, mode, error |
  | `[:agentic, :session, :resume]` | — | session_id, turns_restored |
  | `[:agentic, :pipeline, :stage, :start]` | — | session_id, stage |
  | `[:agentic, :pipeline, :stage, :stop]` | duration | session_id, stage |
  | `[:agentic, :llm_call, :start]` | — | session_id, model_tier, model_selection_mode |
  | `[:agentic, :llm_call, :stop]` | duration, input_tokens, output_tokens, cost_usd | session_id, model_tier, model_selection_mode, route, provider |
  | `[:agentic, :tool, :start]` | — | session_id, tool_name |
  | `[:agentic, :tool, :stop]` | duration, output_bytes | session_id, tool_name, success |
  | `[:agentic, :context, :compact]` | messages_before, messages_after, pct_before, pct_after | session_id |
  | `[:agentic, :context, :cost_limit]` | cost_usd, limit_usd | session_id |
  | `[:agentic, :phase, :transition]` | — | session_id, mode, from, to |
  | `[:agentic, :mode_router, :route]` | — | session_id, mode, phase, stop_reason, action |
  | `[:agentic, :commitment, :detected]` | continuations | session_id |
  | `[:agentic, :plan, :created]` | step_count | session_id |
  | `[:agentic, :plan, :step, :complete]` | — | session_id, step_index, total_steps |
  | `[:agentic, :plan, :all_complete]` | — | session_id, total_steps |
  | `[:agentic, :circuit_breaker, :trip]` | failure_count | tool_name |
  | `[:agentic, :circuit_breaker, :recover]` | — | tool_name |
  | `[:agentic, :model_router, :refresh]` | duration, primary_count, lightweight_count | — |
  | `[:agentic, :model_router, :resolve, :start]` | — | session_id, selection_mode |
  | `[:agentic, :model_router, :resolve, :stop]` | duration, route_count | session_id, selection_mode, selected_provider, selected_model_id, complexity, preference, error |
  | `[:agentic, :model_router, :auto_select]` | — | preference, selected_provider, selected_model_id, complexity, error |
  | `[:agentic, :model_router, :auto, :selected]` | — | session_id, complexity, needs_vision, needs_audio, needs_reasoning, needs_large_context, estimated_input_tokens, preference, selected_model, selected_provider |
  | `[:agentic, :model_router, :auto, :fallback]` | — | session_id, reason |
  | `[:agentic, :model_router, :analysis, :start]` | — | method, session_id, request_length |
  | `[:agentic, :model_router, :analysis, :stop]` | duration | method, session_id, complexity, needs_vision, needs_audio, needs_reasoning, needs_large_context, estimated_input_tokens, required_capabilities |
  | `[:agentic, :model_router, :analysis, :fallback]` | — | session_id, from, to, reason |
  | `[:agentic, :model_router, :analysis, :parse_failure]` | — | — |
  | `[:agentic, :model_router, :selection, :start]` | — | session_id, preference, request_length, model_filter |
  | `[:agentic, :model_router, :selection, :stop]` | duration, candidate_count, best_score | session_id, preference, model_filter, complexity, selected_provider, selected_model_id, selected_label, needs_vision, needs_reasoning, needs_large_context, top3, error |
  | `[:agentic, :model_router, :filter, :rejected]` | — | filter, reason |
  | `[:agentic, :memory, :ingest]` | fact_count | workspace_id |
  | `[:agentic, :memory, :evict]` | evicted_count, remaining_count | workspace_id |
  | `[:agentic, :memory, :retrieval, :stop]` | duration, context_chars, cache_hit | workspace_id, incremental |
  | `[:agentic, :subagent, :spawn]` | — | session_id, parent_session_id, depth |
  | `[:agentic, :subagent, :complete]` | duration, cost, steps | session_id, parent_session_id |
  | `[:agentic, :subagent, :error]` | duration | session_id, parent_session_id, error |
  | `[:agentic, :orchestration, :turn]` | — | session_id, strategy, mode, phase, stop_reason |
  | `[:agentic, :orchestration, :tool_executed]` | duration, output_bytes | session_id, strategy, mode, tool_name, success |
  """

  @doc """
  Emit a telemetry event with the standard `[:agentic]` prefix.
  """
  @spec event([atom()], map(), map()) :: :ok
  def event(event_suffix, measurements \\ %{}, metadata \\ %{}) do
    :telemetry.execute([:agentic | event_suffix], measurements, metadata)
  rescue
    _ -> :ok
  end

  @doc """
  Execute a function wrapped in start/stop telemetry events.
  """
  @spec span([atom()], [atom()], map(), map(), (-> result)) :: result when result: var
  def span(start_suffix, stop_suffix, start_measurements \\ %{}, metadata \\ %{}, fun) do
    start_time = System.monotonic_time()
    event(start_suffix, start_measurements, metadata)

    try do
      result = fun.()
      duration = System.monotonic_time() - start_time
      event(stop_suffix, Map.put(start_measurements, :duration, duration), metadata)
      result
    rescue
      e ->
        duration = System.monotonic_time() - start_time

        event(
          stop_suffix,
          Map.put(start_measurements, :duration, duration),
          Map.put(metadata, :error, true)
        )

        reraise e, __STACKTRACE__
    end
  end
end
