defmodule Agentic.Persistence.TranscriptLocalTest do
  use ExUnit.Case, async: true

  alias Agentic.Persistence.Transcript.Local

  setup do
    workspace = Path.join(System.tmp_dir!(), "agentic_transcript_#{:rand.uniform(999_999)}")
    File.mkdir_p!(workspace)
    on_exit(fn -> File.rm_rf!(workspace) end)
    {:ok, workspace: workspace}
  end

  describe "append/3" do
    test "appends events as JSONL lines", %{workspace: workspace} do
      opts = [workspace: workspace]
      event = %{"type" => "user_message", "text" => "hello", "turn" => 1}

      assert :ok = Local.append("sess-1", event, opts)

      {:ok, events} = Local.load("sess-1", opts)
      assert length(events) == 1
      assert hd(events)["type"] == "user_message"
      assert hd(events)["text"] == "hello"
      assert hd(events)["timestamp"] != nil
    end

    test "appends multiple events in order", %{workspace: workspace} do
      opts = [workspace: workspace]

      Local.append("sess-2", %{"turn" => 1, "text" => "first"}, opts)
      Local.append("sess-2", %{"turn" => 2, "text" => "second"}, opts)

      {:ok, events} = Local.load("sess-2", opts)
      assert length(events) == 2
      assert Enum.at(events, 0)["text"] == "first"
      assert Enum.at(events, 1)["text"] == "second"
    end
  end

  describe "load/2" do
    test "returns not_found for nonexistent session", %{workspace: workspace} do
      assert {:error, :not_found} = Local.load("no-such-session", workspace: workspace)
    end
  end

  describe "load_since/3" do
    test "returns events after given turn", %{workspace: workspace} do
      opts = [workspace: workspace]

      Local.append("sess-3", %{"turn" => 1, "text" => "a"}, opts)
      Local.append("sess-3", %{"turn" => 2, "text" => "b"}, opts)
      Local.append("sess-3", %{"turn" => 3, "text" => "c"}, opts)

      {:ok, events} = Local.load_since("sess-3", 1, opts)
      assert length(events) == 2
      assert Enum.at(events, 0)["text"] == "b"
      assert Enum.at(events, 1)["text"] == "c"
    end
  end

  describe "list_sessions/2" do
    test "lists session summaries", %{workspace: workspace} do
      opts = [workspace: workspace]

      Local.append("sess-a", %{"turn" => 1, "type" => "start"}, opts)
      Local.append("sess-b", %{"turn" => 1, "type" => "start"}, opts)

      {:ok, summaries} = Local.list_sessions(workspace, opts)
      assert length(summaries) == 2

      ids = Enum.map(summaries, & &1.session_id) |> Enum.sort()
      assert ids == ["sess-a", "sess-b"]
    end

    test "returns empty list when no sessions", %{workspace: workspace} do
      {:ok, summaries} = Local.list_sessions(workspace, workspace: workspace)
      assert summaries == []
    end

    test "includes event count in summary", %{workspace: workspace} do
      opts = [workspace: workspace]

      Local.append("sess-c", %{"turn" => 1}, opts)
      Local.append("sess-c", %{"turn" => 2}, opts)

      {:ok, summaries} = Local.list_sessions(workspace, opts)
      summary = Enum.find(summaries, &(&1.session_id == "sess-c"))
      assert summary.event_count == 2
    end
  end

  describe "custom base_dir" do
    test "uses custom base directory", %{workspace: workspace} do
      opts = [workspace: workspace, base_dir: ".custom/sessions"]

      assert :ok = Local.append("sess-x", %{"turn" => 1}, opts)
      {:ok, events} = Local.load("sess-x", opts)
      assert length(events) == 1
    end
  end
end
