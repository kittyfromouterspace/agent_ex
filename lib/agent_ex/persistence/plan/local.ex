defmodule AgentEx.Persistence.Plan.Local do
  @moduledoc """
  JSON file-based plan backend.

  Stores plans as JSON at `<workspace>/.agent_ex/plans/<plan_id>.json`.
  """

  @behaviour AgentEx.Persistence.Plan

  @impl true
  def create(plan, opts) do
    path = plan_path(plan.id, opts)
    File.mkdir_p!(Path.dirname(path))
    File.write(path, Jason.encode!(plan, pretty: true))
    {:ok, plan}
  end

  @impl true
  def get(plan_id, opts) do
    path = plan_path(plan_id, opts)

    case File.read(path) do
      {:ok, content} ->
        {:ok, Jason.decode!(content, keys: :atoms)}

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def update_step(plan_id, step_index, updates, opts) do
    case get(plan_id, opts) do
      {:ok, plan} ->
        steps = plan.steps || []

        if step_index >= 0 and step_index < length(steps) do
          updated_step =
            Enum.at(steps, step_index)
            |> Map.merge(updates)

          steps = List.replace_at(steps, step_index, updated_step)
          plan = %{plan | steps: steps}

          path = plan_path(plan_id, opts)
          File.write(path, Jason.encode!(plan, pretty: true))
          {:ok, plan}
        else
          {:error, {:invalid_step_index, step_index}}
        end

      {:error, _} = err ->
        err
    end
  end

  @impl true
  def list_plans(workspace, opts) do
    dir = plans_dir(workspace, opts)

    case File.ls(dir) do
      {:ok, files} ->
        summaries =
          files
          |> Enum.filter(&String.ends_with?(&1, ".json"))
          |> Enum.map(fn file ->
            plan_id = String.replace_suffix(file, ".json", "")
            path = Path.join(dir, file)

            case File.read(path) do
              {:ok, content} ->
                plan = Jason.decode!(content, keys: :atoms)
                steps = plan.steps || []
                completed = Enum.count(steps, &(&1.status == :complete))

                %{
                  id: plan_id,
                  goal: plan.goal || "",
                  step_count: length(steps),
                  completed_count: completed
                }

              _ ->
                nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        {:ok, summaries}

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp plan_path(plan_id, opts) do
    workspace = Keyword.fetch!(opts, :workspace)
    Path.join(plans_dir(workspace, opts), "#{plan_id}.json")
  end

  defp plans_dir(workspace, opts) do
    base = Keyword.get(opts, :base_dir, ".agent_ex/plans")
    Path.join(workspace, base)
  end
end
