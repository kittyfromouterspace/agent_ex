defmodule Agentic.Loop.Stages.WorkspaceSnapshotTest do
  use ExUnit.Case, async: true

  alias Agentic.Loop.Stages.WorkspaceSnapshot

  import Agentic.TestHelpers

  defp passthrough, do: fn ctx -> {:ok, ctx} end

  describe "first turn (turns_used == 0)" do
    test "gathers snapshot and injects message" do
      workspace = create_test_workspace()
      File.write!(Path.join(workspace, "README.md"), "# Test Project\nSome docs")
      File.write!(Path.join(workspace, "mix.exs"), "defmodule Mixfile do\nend")

      ctx =
        build_ctx(
          metadata: %{workspace: workspace, workspace_id: "ws-test"},
          messages: [%{"role" => "system", "content" => "You are helpful."}]
        )

      assert {:ok, result} = WorkspaceSnapshot.call(ctx, passthrough())
      assert result.workspace_snapshot != nil
      assert length(result.messages) == 2

      snapshot_msg = Enum.find(result.messages, fn m -> m["role"] == "user" end)
      assert String.contains?(snapshot_msg["content"], "Workspace context")
      assert String.contains?(snapshot_msg["content"], "Test Project")
    end

    test "uses on_workspace_snapshot callback when provided" do
      workspace = create_test_workspace()

      custom_snapshot = "Custom workspace info"

      on_snapshot = fn _path ->
        {:ok, custom_snapshot}
      end

      ctx =
        build_ctx(
          metadata: %{workspace: workspace, workspace_id: "ws-test"},
          callbacks: mock_callbacks(%{on_workspace_snapshot: on_snapshot}),
          messages: [%{"role" => "system", "content" => "sys"}]
        )

      assert {:ok, result} = WorkspaceSnapshot.call(ctx, passthrough())
      assert result.workspace_snapshot == custom_snapshot
    end

    test "falls back to auto-gather when callback returns error" do
      workspace = create_test_workspace()
      File.write!(Path.join(workspace, "mix.exs"), "defmodule Mixfile do\nend")

      on_snapshot = fn _path -> {:error, :not_available} end

      ctx =
        build_ctx(
          metadata: %{workspace: workspace, workspace_id: "ws-test"},
          callbacks: mock_callbacks(%{on_workspace_snapshot: on_snapshot}),
          messages: [%{"role" => "system", "content" => "sys"}]
        )

      assert {:ok, result} = WorkspaceSnapshot.call(ctx, passthrough())
      assert result.workspace_snapshot != nil
    end

    test "includes file tree in snapshot" do
      workspace = create_test_workspace()
      File.mkdir_p!(Path.join(workspace, "lib"))
      File.write!(Path.join([workspace, "lib", "app.ex"]), "defmodule App do end")

      ctx =
        build_ctx(
          metadata: %{workspace: workspace, workspace_id: "ws-test"},
          messages: [%{"role" => "system", "content" => "sys"}]
        )

      assert {:ok, result} = WorkspaceSnapshot.call(ctx, passthrough())
      assert String.contains?(result.workspace_snapshot, "File Tree")
    end

    test "includes instruction files when present" do
      workspace = create_test_workspace()
      File.write!(Path.join(workspace, "AGENTS.md"), "# Agent Instructions\nDo stuff")

      ctx =
        build_ctx(
          metadata: %{workspace: workspace, workspace_id: "ws-test"},
          messages: [%{"role" => "system", "content" => "sys"}]
        )

      assert {:ok, result} = WorkspaceSnapshot.call(ctx, passthrough())
      assert String.contains?(result.workspace_snapshot, "AGENTS.md")
      assert String.contains?(result.workspace_snapshot, "Agent Instructions")
    end

    test "skips snapshot when workspace_snapshot already set" do
      workspace = create_test_workspace()

      ctx =
        build_ctx(
          metadata: %{workspace: workspace, workspace_id: "ws-test"},
          messages: [%{"role" => "system", "content" => "sys"}]
        )
        |> Map.put(:workspace_snapshot, "existing snapshot")

      assert {:ok, result} = WorkspaceSnapshot.call(ctx, passthrough())
      assert result.workspace_snapshot == "existing snapshot"
      assert result.messages == ctx.messages
    end
  end

  describe "subsequent turns (turns_used > 0)" do
    test "passes through without gathering snapshot" do
      workspace = create_test_workspace()

      ctx =
        build_ctx(metadata: %{workspace: workspace, workspace_id: "ws-test"})
        |> Map.put(:turns_used, 1)

      assert {:ok, result} = WorkspaceSnapshot.call(ctx, passthrough())
      assert result.workspace_snapshot == nil
      assert result.messages == ctx.messages
    end
  end
end
