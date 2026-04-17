defmodule Agentic.Protocol.ACP.Quirks do
  @moduledoc """
  Agent-specific quirks and workarounds for ACP implementations.

  Different ACP agents have non-standard behaviors that need special handling.
  This module centralizes those quirks so the generic ACP client can work
  correctly with all agents without per-agent modules.

  Derived from https://github.com/openclaw/acpx/blob/main/src/acp/agent-command.ts

  ## Known Quirks

  | Agent | Quirk |
  |-------|-------|
  | Gemini | Version detection; < 0.33.0 needs `--experimental-acp` |
  | Claude | 60s session creation timeout |
  | Copilot | Pre-flight `--help` check for ACP support |
  | Qoder | Extra args `--max-turns`, `--allowed-tools` |
  | Droid | Different subcommand structure |
  | Gemini | 15s startup timeout |
  """

  require Logger

  @doc "Mutate command args for agent-specific requirements."
  @spec mutate_args(String.t(), [String.t()], keyword()) :: {String.t(), [String.t()]}
  def mutate_args(command, args, opts \\ []) do
    basename = Path.basename(command)

    cond do
      gemini?(basename, args) ->
        mutate_gemini_args(command, args)

      qoder?(basename, args) ->
        mutate_qoder_args(command, args, opts)

      copilot?(basename, args) ->
        {command, args}

      droid?(basename, args) ->
        {command, args}

      true ->
        {command, args}
    end
  end

  @doc "Get agent-specific timeout for startup."
  @spec startup_timeout(String.t(), [String.t()]) :: non_neg_integer()
  def startup_timeout(command, args) do
    basename = Path.basename(command)

    cond do
      gemini?(basename, args) -> 15_000
      claude?(basename, args) -> 15_000
      copilot?(basename, args) -> 20_000
      true -> 10_000
    end
  end

  @doc "Get agent-specific timeout for session creation."
  @spec session_create_timeout(String.t(), [String.t()]) :: non_neg_integer()
  def session_create_timeout(command, args) do
    basename = Path.basename(command)

    if claude?(basename, args) do
      60_000
    else
      15_000
    end
  end

  @doc "Get agent-specific grace period after stdin close before SIGTERM."
  @spec close_grace_ms(String.t(), [String.t()]) :: non_neg_integer()
  def close_grace_ms(command, args) do
    basename = Path.basename(command)

    if qoder?(basename, args) do
      750
    else
      100
    end
  end

  @doc "Check if stdout lines from this agent should be filtered."
  @spec should_filter_stdout?(String.t(), [String.t()]) :: boolean()
  def should_filter_stdout?(command, args) do
    basename = Path.basename(command)
    qoder?(basename, args)
  end

  @doc "Filter non-JSON stdout lines for agents that produce them."
  @spec filter_non_json_lines(String.t()) :: String.t()
  def filter_non_json_lines(output) do
    output
    |> String.split("\n", trim: false)
    |> Enum.filter(fn line ->
      trimmed = String.trim(line)

      if trimmed == "" do
        true
      else
        String.starts_with?(trimmed, "{") or String.starts_with?(trimmed, "[")
      end
    end)
    |> Enum.join("\n")
  end

  @doc "Check if agent needs pre-flight validation."
  @spec needs_preflight?(String.t(), [String.t()]) :: boolean()
  def needs_preflight?(command, args) do
    basename = Path.basename(command)
    copilot?(basename, args)
  end

  @doc "Run pre-flight validation for agents that need it."
  @spec preflight_check(String.t(), [String.t()]) :: :ok | {:error, term()}
  def preflight_check(command, args) do
    basename = Path.basename(command)

    if copilot?(basename, args) do
      copilot_preflight_check(command)
    else
      :ok
    end
  end

  @doc "Infer tool kind from tool title when agent doesn't provide one."
  @spec infer_tool_kind(String.t() | nil) :: atom()
  def infer_tool_kind(nil), do: :other

  def infer_tool_kind(title) when is_binary(title) do
    down = String.downcase(title)

    cond do
      String.contains?(down, "read") or String.contains?(down, "view") or
        String.contains?(down, "open") or String.contains?(down, "get ") ->
        :read

      String.contains?(down, "edit") or String.contains?(down, "write") or
        String.contains?(down, "modify") or String.contains?(down, "create") ->
        :edit

      String.contains?(down, "delete") or String.contains?(down, "remove") ->
        :delete

      String.contains?(down, "move") or String.contains?(down, "rename") ->
        :move

      String.contains?(down, "search") or String.contains?(down, "find") or
          String.contains?(down, "grep") ->
        :search

      String.contains?(down, "bash") or String.contains?(down, "run") or
        String.contains?(down, "exec") or String.contains?(down, "shell") ->
        :execute

      String.contains?(down, "think") or String.contains?(down, "reason") ->
        :think

      String.contains?(down, "fetch") or String.contains?(down, "http") ->
        :fetch

      true ->
        :other
    end
  end

  # --- Agent identification ---

  defp gemini?(basename, args) do
    basename == "gemini" and "--acp" in args
  end

  defp claude?(basename, args) do
    basename == "claude" or basename == "claude-agent-acp" or
      "claude-agent-acp" in (args || [])
  end

  defp copilot?(basename, args) do
    basename == "copilot" and "--acp" in (args || [])
  end

  defp qoder?(basename, args) do
    basename == "qodercli" and "--acp" in (args || [])
  end

  defp droid?(basename, _args) do
    basename == "droid"
  end

  # --- Agent-specific mutations ---

  defp mutate_gemini_args(command, args) do
    version = detect_gemini_version(command)

    if version && Version.compare(version, %Version{major: 0, minor: 33, patch: 0}) == :lt do
      args =
        Enum.map(args, fn
          "--acp" -> "--experimental-acp"
          other -> other
        end)

      {command, args}
    else
      {command, args}
    end
  end

  defp mutate_qoder_args(command, args, opts) do
    extra_args = []

    extra_args =
      if max_turns = opts[:max_turns] do
        extra_args ++ ["--max-turns", to_string(max_turns)]
      else
        extra_args
      end

    extra_args =
      if allowed_tools = opts[:allowed_tools] do
        tools_str = Enum.join(allowed_tools, ",")
        extra_args ++ ["--allowed-tools", tools_str]
      else
        extra_args
      end

    {command, args ++ extra_args}
  end

  defp detect_gemini_version(command) do
    case System.cmd(command, ["--version"], stderr_to_stdout: true) do
      {output, 0} ->
        case Regex.run(~r/(\d+\.\d+\.\d+)/, output) do
          [_, version_str] ->
            case Version.parse(version_str) do
              {:ok, version} -> version
              :error -> nil
            end

          _ ->
            nil
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp copilot_preflight_check(command) do
    case System.cmd(command, ["--help"], stderr_to_stdout: true) do
      {output, 0} ->
        if String.contains?(output, "--acp") or String.contains?(output, "acp") do
          :ok
        else
          Logger.warning("Copilot CLI does not appear to support --acp flag")
          {:error, :copilot_acp_unsupported}
        end

      {_, exit_code} ->
        {:error, {:copilot_help_failed, exit_code}}
    end
  rescue
    e ->
      {:error, {:copilot_preflight_error, e}}
  end
end
