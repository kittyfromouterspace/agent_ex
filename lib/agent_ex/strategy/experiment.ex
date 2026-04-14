defmodule AgentEx.Strategy.Experiment do
  @moduledoc """
  Experiment runner for head-to-head strategy comparison.

  Runs the same prompts through multiple strategies with configurable
  repetitions, then computes comparison metrics.
  """

  defstruct [
    :id,
    :name,
    :description,
    :strategies,
    :prompts,
    :repetitions,
    :base_opts,
    :results,
    :status
  ]

  @type t :: %__MODULE__{
          id: term(),
          name: String.t() | nil,
          description: String.t() | nil,
          strategies: [atom()],
          prompts: [String.t()],
          repetitions: pos_integer(),
          base_opts: keyword(),
          results: [result()] | nil,
          status: atom() | nil
        }

  @type result :: %{
          strategy: atom(),
          prompt: String.t(),
          repetition: pos_integer(),
          result: {:ok, map()} | {:error, term()},
          duration_ms: non_neg_integer()
        }

  @type comparison :: %{
          strategy: atom(),
          run_count: non_neg_integer(),
          success_count: non_neg_integer(),
          success_rate: float(),
          avg_duration_ms: float(),
          avg_cost: float(),
          avg_tokens: non_neg_integer(),
          avg_tool_calls: non_neg_integer()
        }

  @doc """
  Run an experiment, collecting results for each (prompt, strategy, repetition) triple.
  """
  @spec run(t()) :: t()
  def run(%__MODULE__{} = experiment) do
    results =
      for prompt <- experiment.prompts,
          strategy <- experiment.strategies,
          rep <- 1..experiment.repetitions do
        opts =
          experiment.base_opts
          |> Keyword.put(:prompt, prompt)
          |> Keyword.put(:strategy, strategy)

        start = System.monotonic_time(:millisecond)
        result = AgentEx.run(opts)
        elapsed = System.monotonic_time(:millisecond) - start

        %{
          strategy: strategy,
          prompt: prompt,
          repetition: rep,
          result: result,
          duration_ms: elapsed
        }
      end

    %{experiment | results: results, status: :complete}
  end

  @doc """
  Compare results across strategies, computing aggregate metrics.
  """
  @spec compare(t()) :: [comparison()]
  def compare(%__MODULE__{results: nil}), do: []
  def compare(%__MODULE__{results: []}), do: []

  def compare(%__MODULE__{results: results, strategies: strategies}) do
    for strategy <- strategies do
      strategy_results = Enum.filter(results, &(&1.strategy == strategy))
      successes = Enum.filter(strategy_results, fn r -> match?({:ok, _}, r.result) end)

      %{
        strategy: strategy,
        run_count: length(strategy_results),
        success_count: length(successes),
        success_rate: length(successes) / max(length(strategy_results), 1),
        avg_duration_ms: avg(strategy_results, & &1.duration_ms),
        avg_cost: avg(successes, fn r -> elem(r.result, 1)[:cost] || 0 end),
        avg_tokens: avg(successes, fn r -> elem(r.result, 1)[:tokens] || 0 end),
        avg_tool_calls: avg(successes, fn r -> elem(r.result, 1)[:steps] || 0 end)
      }
    end
  end

  defp avg(list, extractor) when is_list(list) and length(list) > 0 do
    list
    |> Enum.map(extractor)
    |> Enum.sum()
    |> Kernel./(length(list))
  end

  defp avg(_, _), do: 0.0
end
