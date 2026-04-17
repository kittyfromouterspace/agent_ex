defmodule Agentic.Persistence.Plan do
  @moduledoc """
  Behaviour for CRUD operations on structured plans with step-level status tracking.

  The `:local` implementation stores JSON files at
  `<workspace>/.agentic/plans/<plan_id>.json`.
  """

  @type plan_struct :: %{
          id: String.t(),
          goal: String.t(),
          steps: [step_struct()]
        }

  @type step_struct :: %{
          index: non_neg_integer(),
          description: String.t(),
          tools: [String.t()],
          verification: String.t(),
          status: :pending | :in_progress | :complete | :failed
        }

  @type plan_summary :: %{
          id: String.t(),
          goal: String.t(),
          step_count: non_neg_integer(),
          completed_count: non_neg_integer()
        }

  @callback create(plan :: plan_struct(), opts :: keyword()) ::
              {:ok, plan_struct()} | {:error, term()}

  @callback get(plan_id :: String.t(), opts :: keyword()) ::
              {:ok, plan_struct()} | {:error, :not_found}

  @callback update_step(
              plan_id :: String.t(),
              step_index :: integer(),
              updates :: map(),
              opts :: keyword()
            ) ::
              {:ok, plan_struct()} | {:error, term()}

  @callback list_plans(workspace :: String.t(), opts :: keyword()) ::
              {:ok, [plan_summary()]} | {:error, term()}
end
