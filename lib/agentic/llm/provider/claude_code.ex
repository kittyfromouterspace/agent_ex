defmodule Agentic.LLM.Provider.ClaudeCode do
  @moduledoc """
  Catalog-only Provider wrapper for the Claude Code CLI.

  The CLI protocol (`Agentic.Protocol.ClaudeCode`) handles the actual
  subprocess; this Provider wrapper exists so Claude Code shows up in
  `Agentic.LLM.Catalog` as an alternative pathway for the Claude family.
  The router groups it under the same `canonical_id` as Anthropic-direct
  and OpenRouter, then scores all three pathways via `ProviderAccount`.

  ## `availability/1`

  Three-state result (the proposal's graded availability):

    * `:unavailable` — `claude` binary not on PATH
    * `:degraded`    — binary present but `~/.claude/auth.json` is
                       missing or expired (CLI re-auths lazily on first
                       call; we still want the router to deprioritize)
    * `:ready`       — binary present and auth file is non-expired

  Note: the `Agentic.LLM.Provider` behaviour does not yet declare an
  `availability/1` callback. That's a follow-up; for now the function
  is plain Elixir and the router consumes it via Worth's
  `ProviderAccount` resolver.
  """

  @behaviour Agentic.LLM.Provider

  alias Agentic.LLM.{Credentials, Model, ProviderAccount}

  @cli_name "claude"

  @impl true
  def id, do: :claude_code

  @impl true
  def label, do: "Claude Code (CLI)"

  # CLI providers don't go through the HTTP transport — the agent loop
  # routes them via `Agentic.Protocol.ClaudeCode`. We surface a no-op
  # transport so the Provider behaviour is satisfied.
  @impl true
  def transport, do: Agentic.LLM.Transport.AnthropicMessages

  @impl true
  def default_base_url, do: nil

  @impl true
  def env_vars, do: []

  @impl true
  def supports, do: MapSet.new([:chat, :tools])

  @impl true
  def request_headers(%Credentials{} = _creds), do: []

  @impl true
  def default_models do
    base = [
      {"claude-sonnet-4", "Claude Sonnet 4 (via Claude Code)", :primary, 200_000, 16_384},
      {"claude-opus-4", "Claude Opus 4 (via Claude Code)", :primary, 200_000, 16_384},
      {"claude-haiku-4", "Claude Haiku 4 (via Claude Code)", :lightweight, 200_000, 8_192}
    ]

    Enum.map(base, fn {id, label, tier, ctx, max_out} ->
      %Model{
        id: id,
        provider: :claude_code,
        label: label,
        context_window: ctx,
        max_output_tokens: max_out,
        # Subscription-included pathways carry zero per-token cost in
        # the catalog so estimated-cost math comes out to $0; the user's
        # ProviderAccount carries the monthly subscription fee for
        # amortization.
        cost: %{input: 0.0, output: 0.0, cache_read: 0.0, cache_write: 0.0},
        capabilities: MapSet.new([:chat, :tools]),
        tier_hint: tier,
        source: :static
      }
    end)
  end

  @impl true
  def fetch_catalog(_creds), do: :not_supported

  @impl true
  def fetch_usage(_creds), do: :not_supported

  @impl true
  def classify_http_error(_status, _body, _headers), do: :default

  @doc """
  Three-state availability for the Claude Code pathway. Used by the
  router-side `ProviderAccount` resolver in Worth to set the
  `availability` field on this provider's account.
  """
  @spec availability(ProviderAccount.t() | nil) ::
          :ready | :degraded | :unavailable
  def availability(_account \\ nil) do
    cond do
      System.find_executable(@cli_name) == nil -> :unavailable
      not auth_file_present?() -> :degraded
      auth_expired?() -> :degraded
      true -> :ready
    end
  end

  defp auth_file_path do
    System.user_home() |> Kernel.||(".") |> Path.join(".claude/auth.json")
  end

  defp auth_file_present? do
    File.exists?(auth_file_path())
  end

  # We don't want to crack open the OAuth file format; if mtime is
  # within the last 30 days assume it's still good. Stale auth files
  # show up as `:degraded`, the CLI re-auths on first use.
  defp auth_expired? do
    case File.stat(auth_file_path()) do
      {:ok, %{mtime: mtime}} ->
        days = mtime_age_days(mtime)
        days > 30

      _ ->
        true
    end
  end

  defp mtime_age_days({{y, mo, d}, {h, mi, s}}) do
    case NaiveDateTime.new(y, mo, d, h, mi, s) do
      {:ok, ndt} ->
        case DateTime.from_naive(ndt, "Etc/UTC") do
          {:ok, dt} ->
            DateTime.diff(DateTime.utc_now(), dt, :day)

          _ ->
            0
        end

      _ ->
        0
    end
  end
end
