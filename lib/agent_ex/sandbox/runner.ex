defmodule AgentEx.Sandbox.Runner do
  @moduledoc """
  Cross-platform sandbox wrapper for agent subprocesses.

  Provides a single entry point that selects the correct OS-level
  isolation mechanism based on `AgentEx.Sandbox.Platform.backend/0`.

  Supports two invocation styles:
  - `wrap_shell/2` — for arbitrary shell commands (e.g. the `bash` tool)
  - `wrap_executable/3` — for executable + argument list (e.g. coding agents)
  """

  require Logger

  alias AgentEx.Sandbox.Platform

  @doc """
  Wraps a shell command string in the platform-appropriate sandbox.

  Returns a string that can be passed to `Port.open({:spawn, command}, ...)`.
  """
  @spec wrap_shell(String.t(), keyword()) :: String.t()
  def wrap_shell(command, opts \\ []) when is_binary(command) do
    workspace = Keyword.fetch!(opts, :workspace)
    agent_dirs = Keyword.get(opts, :agent_dirs, [])

    case Platform.backend() do
      :bubblewrap ->
        bwrap_shell(command, workspace, agent_dirs)

      :wsl2_bwrap ->
        wsl2_bwrap_shell(command, workspace, agent_dirs)

      :macos_sandbox ->
        # macOS App Sandbox is inherited from the parent process;
        # no wrapper needed here.
        command

      :windows_restricted ->
        log_windows_warning()
        command
    end
  end

  @doc """
  Wraps an executable path and argument list in the platform-appropriate sandbox.

  Returns `{executable, args, extra_env}` suitable for
  `Port.open({:spawn_executable, executable}, [:binary, :exit_status, {:args, args} | extra_env])`.
  """
  @spec wrap_executable(String.t(), [String.t()], keyword()) :: {String.t(), [String.t()], keyword()}
  def wrap_executable(executable, args, opts \\ []) do
    workspace = Keyword.fetch!(opts, :workspace)
    agent_dirs = Keyword.get(opts, :agent_dirs, [])

    case Platform.backend() do
      :bubblewrap ->
        bwrap_executable(executable, args, workspace, agent_dirs)

      :wsl2_bwrap ->
        wsl2_bwrap_executable(executable, args, workspace, agent_dirs)

      :macos_sandbox ->
        {executable, args, []}

      :windows_restricted ->
        log_windows_warning()
        {executable, args, []}
    end
  end

  # --- Linux bubblewrap ---

  defp bwrap_shell(command, workspace, agent_dirs) do
    bwrap = bwrap_executable()
    args = bwrap_args(workspace, agent_dirs)
    "#{bwrap} #{args} -- /bin/sh -c #{shell_escape(command)}"
  end

  defp bwrap_executable(executable, args, workspace, agent_dirs) do
    bwrap = bwrap_executable()
    bwrap_args_list = bwrap_args_list(workspace, agent_dirs)
    {bwrap, bwrap_args_list ++ ["--", executable] ++ args, []}
  end

  defp bwrap_executable do
    bundled = bundled_bwrap_path()

    if bundled != nil and File.exists?(bundled) do
      bundled
    else
      case System.find_executable("bwrap") do
        nil ->
          Logger.warning(
            "AgentEx.Sandbox: bwrap not found in PATH. " <>
              "Falling back to system bwrap (may fail)."
          )

          "bwrap"

        exe ->
          exe
      end
    end
  end

  defp bundled_bwrap_path do
    case :os.type() do
      {:unix, :linux} ->
        # Prefer a bundled static binary in the OTP release priv dir
        priv = Application.app_dir(:agent_ex, "priv/bin/bwrap")
        if File.exists?(priv), do: priv, else: nil

      _ ->
        nil
    end
  end

  defp bwrap_args(workspace, agent_dirs) do
    bwrap_args_list(workspace, agent_dirs) |> Enum.map_join(" ", &shell_escape/1)
  end

  defp bwrap_args_list(workspace, agent_dirs) do
    base =
      [
        "--ro-bind", "/usr", "/usr",
        "--ro-bind", "/bin", "/bin",
        "--ro-bind", "/lib", "/lib",
        "--ro-bind", "/lib64", "/lib64",
        "--ro-bind", "/etc", "/etc",
        "--dev", "/dev",
        "--proc", "/proc",
        "--tmpfs", "/tmp",
        "--dir", "/run",
        "--unshare-all",
        "--die-with-parent",
        "--chdir", "/workspace"
      ] ++
      bind_args(workspace, "/workspace", :rw)

    agent_binds =
      agent_dirs
      |> Enum.with_index()
      |> Enum.flat_map(fn {dir, idx} ->
        bind_args(dir, "/agent/dir#{idx}", :rw)
      end)

    base ++ agent_binds
  end

  defp bind_args(host_path, container_path, :rw) do
    if File.dir?(host_path) or not File.exists?(host_path) do
      # Ensure the directory exists so bwrap can bind-mount it
      File.mkdir_p!(host_path)
      ["--bind", host_path, container_path]
    else
      # Host path is a file; bind it as a file
      ["--bind", host_path, container_path]
    end
  end

  # --- WSL2 bubblewrap ---

  defp wsl2_bwrap_shell(command, workspace, agent_dirs) do
    ws_wsl = windows_to_wsl_path(workspace)
    dirs_wsl = Enum.map(agent_dirs, &windows_to_wsl_path/1)
    args = bwrap_args_list(ws_wsl, dirs_wsl) |> Enum.map_join(" ", &shell_escape/1)
    "wsl.exe -- bwrap #{args} --chdir /workspace -- /bin/sh -c #{shell_escape(command)}"
  end

  defp wsl2_bwrap_executable(executable, args, workspace, agent_dirs) do
    ws_wsl = windows_to_wsl_path(workspace)
    dirs_wsl = Enum.map(agent_dirs, &windows_to_wsl_path/1)
    bwrap_args_list = bwrap_args_list(ws_wsl, dirs_wsl)
    {"wsl.exe", ["--", "bwrap"] ++ bwrap_args_list ++ ["--chdir", "/workspace", "--", executable] ++ args, []}
  end

  defp windows_to_wsl_path(<<drive::binary-size(1), ":", rest::binary>>) do
    "/mnt/#{String.downcase(drive)}#{String.replace(rest, "\\", "/")}"
  end

  defp windows_to_wsl_path(path) do
    String.replace(path, "\\", "/")
  end

  # --- Helpers ---

  defp shell_escape(str) do
    # Simple single-quote escaping for shell safety
    "'" <> String.replace(str, "'", "'\"'\"'") <> "'"
  end

  defp log_windows_warning do
    case Platform.warning() do
      nil -> :ok
      msg -> Logger.warning("AgentEx.Sandbox.Runner: #{msg}")
    end
  end
end
