defmodule AgentEx.Strategy do
  @moduledoc """
  Behaviour for orchestration strategies.

  A strategy controls how the agent loop runs: it can modify opts before
  each run, decide whether to re-run, react to events, and contribute
  telemetry tags.

  ## Callbacks

  | Callback | When | Purpose |
  |----------|------|---------|
  | `init/1` | Before first run | Strategy-specific setup |
  | `prepare_run/2` | Before each `AgentEx.run` | Modify profile, mode, system prompt, etc. |
  | `handle_result/3` | After each run completes | Decide: done, rerun, or record |
  | `handle_event/2` | On `Context.emit_event/2` | Reactive adaptation |
  | `telemetry_tags/0` | In telemetry events | Strategy-specific dimensions |
  """

  @type state :: term()
  @type ctx :: AgentEx.Loop.Context.t()
  @type opts :: keyword()

  @callback id() :: atom()

  @callback display_name() :: String.t()

  @callback description() :: String.t()

  @callback init(opts :: keyword()) :: {:ok, state()} | {:error, term()}

  @callback prepare_run(opts :: keyword(), state :: state()) ::
              {:ok, prepared_opts :: keyword(), new_state :: state()} | {:error, term()}

  @callback handle_result(
              result :: {:ok, map()} | {:error, term()},
              opts :: keyword(),
              state :: state()
            ) ::
              {:ok, new_state :: state()}
              | {:rerun, new_opts :: keyword(), new_state :: state()}
              | {:done, final_result :: map(), new_state :: state()}
              | {:error, term()}

  @callback handle_event(event :: tuple(), state :: state()) ::
              {:ok, new_state :: state()} | {:swap, strategy_id :: atom()} | :ignore

  @callback telemetry_tags() :: [{atom(), term()}]

  @optional_callbacks [handle_event: 2, telemetry_tags: 0]
end
