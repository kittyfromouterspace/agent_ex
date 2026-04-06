defmodule AgentEx.Storage.Local do
  @moduledoc "Local filesystem storage backend."

  @behaviour AgentEx.Storage.Backend

  def name, do: :local

  @impl true
  def read(config, path) do
    config.root |> resolve_path(path) |> File.read()
  end

  @impl true
  def write(config, path, content) do
    full = resolve_path(config.root, path)
    full |> Path.dirname() |> File.mkdir_p!()
    File.write(full, content)
  end

  @impl true
  def exists?(config, path), do: config.root |> resolve_path(path) |> File.exists?()
  @impl true
  def dir?(config, path), do: config.root |> resolve_path(path) |> File.dir?()
  @impl true
  def ls(config, path), do: config.root |> resolve_path(path) |> File.ls()

  @impl true
  def rm_rf(config, path) do
    config.root |> resolve_path(path) |> File.rm_rf!()
    :ok
  end

  @impl true
  def mkdir_p(config, path), do: config.root |> resolve_path(path) |> File.mkdir_p()
  @impl true
  def materialize_local(config, path), do: {:ok, resolve_path(config.root, path)}

  defp resolve_path(root, "."), do: root
  defp resolve_path(root, path), do: Path.join(root, path)
end
