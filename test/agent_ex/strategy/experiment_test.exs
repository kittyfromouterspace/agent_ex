defmodule AgentEx.Strategy.ExperimentTest do
  use ExUnit.Case, async: true

  alias AgentEx.Strategy.Experiment

  describe "compare/1" do
    test "returns empty list for nil results" do
      exp = %Experiment{results: nil, strategies: [:default]}
      assert Experiment.compare(exp) == []
    end

    test "returns empty list for empty results" do
      exp = %Experiment{results: [], strategies: [:default]}
      assert Experiment.compare(exp) == []
    end

    test "computes metrics per strategy" do
      results = [
        %{
          strategy: :default,
          prompt: "hello",
          repetition: 1,
          result: {:ok, %{cost: 0.01, tokens: 100, steps: 3}},
          duration_ms: 500
        },
        %{
          strategy: :default,
          prompt: "hello",
          repetition: 2,
          result: {:ok, %{cost: 0.02, tokens: 200, steps: 5}},
          duration_ms: 1000
        },
        %{
          strategy: :stigmergy,
          prompt: "hello",
          repetition: 1,
          result: {:ok, %{cost: 0.005, tokens: 80, steps: 2}},
          duration_ms: 300
        },
        %{
          strategy: :stigmergy,
          prompt: "hello",
          repetition: 2,
          result: {:error, :timeout},
          duration_ms: 2000
        }
      ]

      exp = %Experiment{results: results, strategies: [:default, :stigmergy]}
      comparisons = Experiment.compare(exp)

      default = Enum.find(comparisons, &(&1.strategy == :default))
      stigmergy = Enum.find(comparisons, &(&1.strategy == :stigmergy))

      assert default.run_count == 2
      assert default.success_count == 2
      assert_in_delta default.success_rate, 1.0, 0.01
      assert_in_delta default.avg_cost, 0.015, 0.001
      assert_in_delta default.avg_duration_ms, 750, 1

      assert stigmergy.run_count == 2
      assert stigmergy.success_count == 1
      assert_in_delta stigmergy.success_rate, 0.5, 0.01
    end
  end

  describe "run/1" do
    test "populates results and sets status to complete" do
      exp = %Experiment{
        id: :test,
        name: "Test",
        strategies: [:default],
        prompts: ["hello"],
        repetitions: 1,
        base_opts: [workspace: "/tmp", callbacks: %{llm_chat: fn _ -> {:ok, %AgentEx.LLM.Response{}} end}],
        results: nil,
        status: :pending
      }

      result = Experiment.run(exp)
      assert result.status == :complete
      assert length(result.results) == 1
    end
  end
end
