defmodule Agentic.Persistence.KnowledgeLocalTest do
  use ExUnit.Case, async: true

  alias Agentic.Persistence.Knowledge.Local

  setup do
    workspace = Path.join(System.tmp_dir!(), "agentic_knowledge_#{:rand.uniform(999_999)}")
    File.mkdir_p!(workspace)
    on_exit(fn -> File.rm_rf!(workspace) end)
    {:ok, workspace: workspace}
  end

  describe "create_entry/2" do
    test "creates an entry and assigns id and timestamp", %{workspace: workspace} do
      opts = [workspace: workspace]

      entry = %{
        content: "The main module is in lib/app.ex",
        entry_type: "fact",
        source: "read_file",
        scope_id: "scope-1",
        metadata: %{},
        confidence: 0.9
      }

      assert {:ok, created} = Local.create_entry(entry, opts)
      assert String.starts_with?(created.id, "ke-")
      assert created.content == "The main module is in lib/app.ex"
      assert created.inserted_at != nil
    end

    test "preserves existing id if provided", %{workspace: workspace} do
      opts = [workspace: workspace]

      entry = %{
        id: "custom-id",
        content: "test",
        entry_type: "fact",
        source: "test",
        metadata: %{},
        confidence: 1.0
      }

      {:ok, created} = Local.create_entry(entry, opts)
      assert created.id == "custom-id"
    end
  end

  describe "get_entry/2" do
    test "returns entry by id", %{workspace: workspace} do
      opts = [workspace: workspace]

      {:ok, created} =
        Local.create_entry(
          %{
            content: "test fact",
            entry_type: "fact",
            source: "test",
            metadata: %{},
            confidence: 0.8
          },
          opts
        )

      {:ok, found} = Local.get_entry(created.id, opts)
      assert found.content == "test fact"
    end

    test "returns not_found for missing entry", %{workspace: workspace} do
      assert {:error, :not_found} = Local.get_entry("no-such-id", workspace: workspace)
    end
  end

  describe "search/2" do
    test "finds entries by keyword", %{workspace: workspace} do
      opts = [workspace: workspace]

      Local.create_entry(
        %{
          content: "Elixir module defined",
          entry_type: "fact",
          source: "test",
          metadata: %{},
          confidence: 0.9
        },
        opts
      )

      Local.create_entry(
        %{
          content: "Python script found",
          entry_type: "fact",
          source: "test",
          metadata: %{},
          confidence: 0.9
        },
        opts
      )

      {:ok, results} = Local.search("elixir", opts)
      assert length(results) == 1
      assert hd(results).content == "Elixir module defined"
    end

    test "returns multiple matches", %{workspace: workspace} do
      opts = [workspace: workspace]

      Local.create_entry(
        %{
          content: "Elixir module A",
          entry_type: "fact",
          source: "test",
          metadata: %{},
          confidence: 0.9
        },
        opts
      )

      Local.create_entry(
        %{
          content: "Elixir module B",
          entry_type: "fact",
          source: "test",
          metadata: %{},
          confidence: 0.9
        },
        opts
      )

      {:ok, results} = Local.search("elixir", opts)
      assert length(results) == 2
    end

    test "returns empty for no matches", %{workspace: workspace} do
      opts = [workspace: workspace]
      {:ok, results} = Local.search("nonexistent", opts)
      assert results == []
    end
  end

  describe "edges" do
    test "creates and retrieves edges", %{workspace: workspace} do
      opts = [workspace: workspace]

      {:ok, e1} =
        Local.create_entry(
          %{
            content: "fact A",
            entry_type: "fact",
            source: "test",
            metadata: %{},
            confidence: 1.0
          },
          opts
        )

      {:ok, e2} =
        Local.create_entry(
          %{
            content: "fact B",
            entry_type: "fact",
            source: "test",
            metadata: %{},
            confidence: 1.0
          },
          opts
        )

      {:ok, edge} = Local.create_edge(e1.id, e2.id, "depends_on", opts)
      assert edge.source_entry_id == e1.id
      assert edge.target_entry_id == e2.id
      assert edge.relation == "depends_on"

      {:ok, edges} = Local.get_edges(e1.id, :from, opts)
      assert length(edges) == 1
    end
  end

  describe "recent/2" do
    test "returns entries filtered by scope_id, sorted by date", %{workspace: workspace} do
      opts = [workspace: workspace]

      Local.create_entry(
        %{
          content: "scope fact 1",
          entry_type: "fact",
          source: "test",
          scope_id: "s1",
          metadata: %{},
          confidence: 1.0
        },
        opts
      )

      Local.create_entry(
        %{
          content: "scope fact 2",
          entry_type: "fact",
          source: "test",
          scope_id: "s1",
          metadata: %{},
          confidence: 1.0
        },
        opts
      )

      Local.create_entry(
        %{
          content: "other scope",
          entry_type: "fact",
          source: "test",
          scope_id: "s2",
          metadata: %{},
          confidence: 1.0
        },
        opts
      )

      {:ok, results} = Local.recent("s1", opts)
      assert length(results) == 2
      assert Enum.all?(results, &(&1.scope_id == "s1"))
    end

    test "respects limit option", %{workspace: workspace} do
      opts = [workspace: workspace]

      for i <- 1..5 do
        Local.create_entry(
          %{
            content: "fact #{i}",
            entry_type: "fact",
            source: "test",
            scope_id: "sl",
            metadata: %{},
            confidence: 1.0
          },
          opts
        )
      end

      {:ok, results} = Local.recent("sl", Keyword.put(opts, :limit, 2))
      assert length(results) == 2
    end
  end
end
