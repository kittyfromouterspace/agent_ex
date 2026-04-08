defmodule AgentEx.TestHelpers do
  @moduledoc "Shared helpers for AgentEx tests."

  @doc "Build mock callbacks with optional overrides."
  def mock_callbacks(overrides \\ %{}) do
    defaults = %{
      llm_chat: &mock_llm_end_turn/1,
      execute_tool: &mock_tool_execute/3
    }

    Map.merge(defaults, overrides)
  end

  def mock_llm_end_turn(_params) do
    {:ok,
     %{
       "content" => [%{"type" => "text", "text" => "Hello! I'm here to help."}],
       "stop_reason" => :end_turn,
       "usage" => %{"input_tokens" => 100, "output_tokens" => 50},
       "cost" => 0.001
     }}
  end

  def mock_llm_tool_use(_params) do
    {:ok,
     %{
       "content" => [
         %{"type" => "text", "text" => "Let me check that file."},
         %{
           "type" => "tool_use",
           "id" => "call_1",
           "name" => "read_file",
           "input" => %{"path" => "test.txt"}
         }
       ],
       "stop_reason" => :tool_use,
       "usage" => %{"input_tokens" => 100, "output_tokens" => 80},
       "cost" => 0.002
     }}
  end

  def mock_tool_execute(name, _input, ctx) do
    {:ok, "Mock result from #{name}", ctx}
  end

  def create_test_workspace do
    path = Path.join(System.tmp_dir!(), "agent_ex_test_#{:rand.uniform(999_999)}")
    File.mkdir_p!(path)
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(path) end)
    path
  end

  @doc "Build a minimal Context for stage tests."
  def build_ctx(overrides \\ []) do
    defaults = [
      session_id: "test-session",
      caller: self(),
      metadata: %{workspace: "/tmp/test", workspace_id: "ws-test"},
      messages: [%{"role" => "system", "content" => "You are a test agent."}],
      callbacks: mock_callbacks()
    ]

    opts = Keyword.merge(defaults, overrides)
    ctx = AgentEx.Loop.Context.new(opts)
    AgentEx.Tools.Activation.init(ctx)
  end

  @doc "Build a Context for agentic_planned mode tests."
  def build_planned_ctx(overrides \\ []) do
    build_ctx(Keyword.merge([mode: :agentic_planned, phase: :plan], overrides))
  end

  @doc "Build a Context for turn_by_turn mode tests."
  def build_turn_by_turn_ctx(overrides \\ []) do
    build_ctx(
      Keyword.merge(
        [
          mode: :turn_by_turn,
          phase: :review,
          callbacks: mock_callbacks(on_human_input: mock_human_callback([{:approve, "ok"}]))
        ],
        overrides
      )
    )
  end

  @doc "Mock human callback that returns a sequence of responses."
  def mock_human_callback(responses) do
    fn _proposal, ctx ->
      case responses do
        [{:approve, _} | _rest] ->
          {:approve, ctx}

        [{:approve, _feedback, _ctx} | _rest] ->
          {:approve, _feedback, ctx}

        [{:abort, reason} | _rest] ->
          {:abort, reason}

        [] ->
          {:abort, "no more responses"}
      end
    end
  end

  @doc "Mock LLM that returns a plan response with the given steps."
  def mock_llm_plan_response(steps) do
    fn _params ->
      text =
        steps
        |> Enum.map_join("\n", fn s ->
          "Step #{s[:index] + 1}: #{s[:description]}"
        end)

      {:ok,
       %{
         "content" => [%{"type" => "text", "text" => text}],
         "stop_reason" => :end_turn,
         "usage" => %{"input_tokens" => 100, "output_tokens" => 80},
         "cost" => 0.002
       }}
    end
  end
end
