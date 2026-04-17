defmodule Agentic.Persistence.Transcript.Local do
  @moduledoc """
  JSONL file-based transcript backend.

  Writes session events as JSONL to `<workspace>/.agentic/sessions/<session_id>.jsonl`.
  """

  @behaviour Agentic.Persistence.Transcript

  @impl true
  def append(session_id, event, opts) do
    path = session_path(session_id, opts)
    File.mkdir_p!(Path.dirname(path))

    line =
      event
      |> Map.put(:timestamp, DateTime.utc_now() |> DateTime.to_iso8601())
      |> Jason.encode!()

    File.write(path, line <> "\n", [:append])
  end

  @impl true
  def load(session_id, opts) do
    path = session_path(session_id, opts)

    case File.read(path) do
      {:ok, content} ->
        events =
          content
          |> String.trim()
          |> String.split("\n")
          |> Enum.filter(&(&1 != ""))
          |> Enum.map(&Jason.decode!/1)

        {:ok, events}

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def load_since(session_id, after_turn, opts) do
    case load(session_id, opts) do
      {:ok, events} ->
        filtered = Enum.filter(events, fn e -> (e["turn"] || 0) > after_turn end)
        {:ok, filtered}

      {:error, _} = err ->
        err
    end
  end

  @impl true
  def list_sessions(workspace, opts) do
    dir = sessions_dir(workspace, opts)

    case File.ls(dir) do
      {:ok, files} ->
        summaries =
          files
          |> Enum.filter(&String.ends_with?(&1, ".jsonl"))
          |> Enum.map(fn file ->
            session_id = String.replace_suffix(file, ".jsonl", "")
            path = Path.join(dir, file)

            case File.read(path) do
              {:ok, content} ->
                lines = String.split(String.trim(content), "\n")
                count = length(lines)

                first =
                  List.first(lines)
                  |> decode_timestamp()

                last =
                  List.last(lines)
                  |> decode_timestamp()

                %{
                  session_id: session_id,
                  workspace: workspace,
                  event_count: count,
                  first_event_at: first,
                  last_event_at: last
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

  defp session_path(session_id, opts) do
    workspace = Keyword.fetch!(opts, :workspace)
    Path.join(sessions_dir(workspace, opts), "#{session_id}.jsonl")
  end

  defp sessions_dir(workspace, opts) do
    base = Keyword.get(opts, :base_dir, ".agentic/sessions")
    Path.join(workspace, base)
  end

  defp decode_timestamp(nil), do: nil

  defp decode_timestamp(line) do
    case Jason.decode(line) do
      {:ok, %{"timestamp" => ts}} when is_binary(ts) ->
        case DateTime.from_iso8601(ts) do
          {:ok, dt, _} -> dt
          _ -> nil
        end

      _ ->
        nil
    end
  end
end
