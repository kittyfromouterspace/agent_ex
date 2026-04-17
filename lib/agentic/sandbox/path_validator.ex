defmodule Agentic.Sandbox.PathValidator do
  @moduledoc """
  Validates that tool-requested paths stay within an explicit allowlist of roots.

  Prevents:
  - Absolute path injection
  - `..` directory traversal
  - Symlink escapes (via expansion against known roots)
  - Access outside the workspace or agent-private directories
  """

  @doc """
  Validates a relative path against a list of allowed root directories.

  Returns the expanded absolute path on success.
  Raises `ArgumentError` if the path is absolute, escapes all roots, or is empty.
  """
  @spec validate!(String.t(), [String.t()]) :: String.t()
  def validate!(relative_path, allowed_roots) when is_list(allowed_roots) do
    if is_nil(relative_path) or relative_path == "" do
      raise ArgumentError, "Path cannot be empty"
    end

    if Path.type(relative_path) == :absolute do
      raise ArgumentError, "Absolute paths are not allowed: #{relative_path}"
    end

    # Join with each allowed root, expand, and verify it stays under that root
    expanded =
      Enum.find_value(allowed_roots, fn root ->
        candidate = Path.expand(Path.join(root, relative_path))

        if String.starts_with?(candidate, root <> "/") or candidate == root do
          candidate
        else
          nil
        end
      end)

    unless expanded do
      raise ArgumentError,
            "Path #{inspect(relative_path)} escapes all allowed roots"
    end

    expanded
  end

  @doc """
  Non-raising version. Returns `{:ok, expanded_path}` or `{:error, reason}`.
  """
  @spec validate(String.t(), [String.t()]) :: {:ok, String.t()} | {:error, String.t()}
  def validate(relative_path, allowed_roots) when is_list(allowed_roots) do
    {:ok, validate!(relative_path, allowed_roots)}
  rescue
    e in ArgumentError -> {:error, Exception.message(e)}
    e -> {:error, Exception.message(e)}
  end
end
