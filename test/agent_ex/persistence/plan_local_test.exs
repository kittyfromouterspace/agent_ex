defmodule AgentEx.Persistence.PlanLocalTest do
  use ExUnit.Case, async: true

  alias AgentEx.Persistence.Plan.Local

  setup do
    workspace = Path.join(System.tmp_dir!(), "agent_ex_plan_#{:rand.uniform(999_999)}")
    File.mkdir_p!(workspace)
    on_exit(fn -> File.rm_rf!(workspace) end)
    {:ok, workspace: workspace}
  end

  describe "create/2" do
    test "creates a plan and writes JSON file", %{workspace: workspace} do
      opts = [workspace: workspace]

      plan = %{
        id: "plan-1",
        goal: "Fix the bug",
        steps: [
          %{
            index: 0,
            description: "Read files",
            tools: ["read_file"],
            verification: "ok",
            status: :pending
          }
        ]
      }

      assert {:ok, result} = Local.create(plan, opts)
      assert result.id == "plan-1"

      {:ok, loaded} = Local.get("plan-1", opts)
      assert loaded.goal == "Fix the bug"
      assert length(loaded.steps) == 1
    end
  end

  describe "get/2" do
    test "returns not_found for nonexistent plan", %{workspace: workspace} do
      assert {:error, :not_found} = Local.get("no-plan", workspace: workspace)
    end
  end

  describe "update_step/4" do
    test "updates step status", %{workspace: workspace} do
      opts = [workspace: workspace]

      plan = %{
        id: "plan-2",
        goal: "Test",
        steps: [
          %{index: 0, description: "Step 1", status: :pending},
          %{index: 1, description: "Step 2", status: :pending}
        ]
      }

      Local.create(plan, opts)
      {:ok, updated} = Local.update_step("plan-2", 0, %{status: :complete}, opts)

      assert Enum.at(updated.steps, 0).status == :complete
      assert Enum.at(updated.steps, 1).status == "pending"

      {:ok, reloaded} = Local.get("plan-2", opts)
      assert Enum.at(reloaded.steps, 0).status in [:complete, "complete"]
    end

    test "returns error for invalid step index", %{workspace: workspace} do
      opts = [workspace: workspace]

      plan = %{
        id: "plan-3",
        goal: "Test",
        steps: [%{index: 0, description: "S1", status: :pending}]
      }

      Local.create(plan, opts)

      assert {:error, {:invalid_step_index, 5}} =
               Local.update_step("plan-3", 5, %{status: :complete}, opts)
    end
  end

  describe "list_plans/2" do
    test "lists plan summaries", %{workspace: workspace} do
      opts = [workspace: workspace]

      Local.create(
        %{
          id: "p-a",
          goal: "Goal A",
          steps: [
            %{index: 0, description: "S1", status: :pending},
            %{index: 1, description: "S2", status: :pending}
          ]
        },
        opts
      )

      Local.update_step("p-a", 0, %{status: :complete}, opts)

      Local.create(
        %{
          id: "p-b",
          goal: "Goal B",
          steps: [
            %{index: 0, description: "S1", status: :pending}
          ]
        },
        opts
      )

      {:ok, summaries} = Local.list_plans(workspace, opts)
      assert length(summaries) == 2

      sa = Enum.find(summaries, &(&1.id == "p-a"))
      assert sa.goal == "Goal A"
      assert sa.step_count == 2
      assert sa.completed_count == 1
    end

    test "returns empty list when no plans", %{workspace: workspace} do
      {:ok, summaries} = Local.list_plans(workspace, workspace: workspace)
      assert summaries == []
    end
  end
end
