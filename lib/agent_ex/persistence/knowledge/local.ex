defmodule AgentEx.Persistence.Knowledge.Local do
  @moduledoc """
  File-based knowledge backend.

  Uses a JSONL index file at `<workspace>/.agent_ex/knowledge.jsonl`.
  Intended for lightweight/no-DB scenarios. Search is keyword-based.
  """

  @behaviour AgentEx.Persistence.Knowledge

  @impl true
  def search(query, opts) do
    entries = load_entries(opts)
    keywords = query |> String.downcase() |> String.split(~r/\s+/)

    results =
      Enum.filter(entries, fn entry ->
        text = (entry.content <> " " <> (entry.metadata[:tags] || "")) |> String.downcase()
        Enum.any?(keywords, &String.contains?(text, &1))
      end)

    {:ok, results}
  end

  @impl true
  def create_entry(entry, opts) do
    path = entries_path(opts)
    File.mkdir_p!(Path.dirname(path))

    entry = Map.put_new(entry, :id, generate_id())
    entry = Map.put_new(entry, :inserted_at, DateTime.utc_now())

    line = Jason.encode!(entry)
    File.write(path, line <> "\n", [:append])
    {:ok, entry}
  end

  @impl true
  def get_entry(entry_id, opts) do
    entries = load_entries(opts)

    case Enum.find(entries, &(&1.id == entry_id)) do
      nil -> {:error, :not_found}
      entry -> {:ok, entry}
    end
  end

  @impl true
  def get_edges(entry_id, _direction, opts) do
    edges = load_edges(opts)

    relevant =
      Enum.filter(edges, fn edge ->
        edge.source_entry_id == entry_id or edge.target_entry_id == entry_id
      end)

    {:ok, relevant}
  end

  @impl true
  def create_edge(from_id, to_id, relation, opts) do
    path = edges_path(opts)
    File.mkdir_p!(Path.dirname(path))

    edge = %{
      id: generate_id(),
      source_entry_id: from_id,
      target_entry_id: to_id,
      relation: relation,
      weight: 1.0
    }

    line = Jason.encode!(edge)
    File.write(path, line <> "\n", [:append])
    {:ok, edge}
  end

  @impl true
  def recent(scope_id, opts) do
    entries = load_entries(opts)

    scoped =
      entries
      |> Enum.filter(&(&1.scope_id == scope_id))
      |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
      |> Enum.take(Keyword.get(opts, :limit, 50))

    {:ok, scoped}
  end

  @impl true
  def supersede(_scope_id, _entity, _relation, _new_value) do
    {:ok, []}
  end

  defp load_entries(opts) do
    path = entries_path(opts)

    case File.read(path) do
      {:ok, content} ->
        content
        |> String.trim()
        |> String.split("\n")
        |> Enum.filter(&(&1 != ""))
        |> Enum.map(fn line ->
          map = Jason.decode!(line, keys: :atoms)

          Map.update!(map, :inserted_at, fn
            %DateTime{} = dt ->
              dt

            s when is_binary(s) ->
              case DateTime.from_iso8601(s) do
                {:ok, dt, _} -> dt
                _ -> nil
              end

            _ ->
              nil
          end)
        end)

      _ ->
        []
    end
  end

  defp load_edges(opts) do
    path = edges_path(opts)

    case File.read(path) do
      {:ok, content} ->
        content
        |> String.trim()
        |> String.split("\n")
        |> Enum.filter(&(&1 != ""))
        |> Enum.map(&Jason.decode!(&1, keys: :atoms))

      _ ->
        []
    end
  end

  defp entries_path(opts) do
    workspace = Keyword.fetch!(opts, :workspace)
    base = Keyword.get(opts, :base_dir, ".agent_ex")
    Path.join(workspace, "#{base}/knowledge.jsonl")
  end

  defp edges_path(opts) do
    workspace = Keyword.fetch!(opts, :workspace)
    base = Keyword.get(opts, :base_dir, ".agent_ex")
    Path.join(workspace, "#{base}/knowledge_edges.jsonl")
  end

  defp generate_id do
    "ke-" <> Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)
  end
end
