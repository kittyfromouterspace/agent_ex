defmodule Agentic.Sandbox.Platform do
  @moduledoc """
  OS-level sandbox capability detection.

  Decisions are based on the operating system (`:os.type/0`), not on the
  presence of specific binaries in `$PATH`. This prevents silent failures
  where a sandbox tool is installed but does not provide meaningful
  isolation on the host platform (e.g. `bwrap` on macOS).
  """

  require Logger

  @type backend :: :bubblewrap | :macos_sandbox | :wsl2_bwrap | :windows_restricted

  @doc """
  Returns the effective sandbox backend for the current operating system.
  """
  @spec backend() :: backend()
  def backend do
    case :os.type() do
      {:unix, :linux} -> :bubblewrap
      {:unix, :darwin} -> :macos_sandbox
      {:win32, _} -> windows_backend()
    end
  end

  @doc """
  Returns a human-readable description of the current sandbox backend.
  """
  @spec backend_name() :: String.t()
  def backend_name do
    case backend() do
      :bubblewrap -> "Linux bubblewrap"
      :macos_sandbox -> "macOS App Sandbox"
      :wsl2_bwrap -> "Windows WSL2 + bubblewrap"
      :windows_restricted -> "Windows restricted token"
    end
  end

  @doc """
  Returns true if the current platform provides strong filesystem isolation.
  Windows without WSL2 is considered weak and will return false.
  """
  @spec strong_isolation?() :: boolean()
  def strong_isolation? do
    case backend() do
      :bubblewrap -> true
      :macos_sandbox -> true
      :wsl2_bwrap -> true
      :windows_restricted -> false
    end
  end

  @doc """
  Returns a warning string if the current platform has weak sandboxing.
  Returns `nil` when isolation is strong.
  """
  @spec warning() :: String.t() | nil
  def warning do
    case backend() do
      :windows_restricted ->
        "WSL2 is not available on this Windows system. " <>
          "Coding agents will run with restricted tokens only. " <>
          "Full filesystem isolation requires WSL2."

      _ ->
        nil
    end
  end

  @doc """
  Logs the platform backend at application startup.
  """
  @spec log_status() :: :ok
  def log_status do
    Logger.info("Agentic.Sandbox: using #{backend_name()}")

    case warning() do
      nil -> :ok
      msg -> Logger.warning("Agentic.Sandbox: #{msg}")
    end

    :ok
  end

  # --- Private ---

  defp windows_backend do
    if wsl2_available?() do
      :wsl2_bwrap
    else
      :windows_restricted
    end
  end

  defp wsl2_available? do
    System.find_executable("wsl.exe") != nil
  end
end
