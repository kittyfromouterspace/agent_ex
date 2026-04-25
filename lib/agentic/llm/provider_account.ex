defmodule Agentic.LLM.ProviderAccount do
  @moduledoc """
  Per-user, per-provider account state used by the multi-pathway router.

  The same model is `:pay_per_token` for someone with a raw API key and
  `:subscription_included` for someone on Pro — so the cost profile lives
  here, not on `Agentic.LLM.Model`.

  Worth (or any other host) is responsible for resolving these from its
  settings storage and pushing them into `ctx.metadata[:provider_accounts]`
  before each agent run; the router pulls them from ctx, never from disk.

  ## Fields

    * `:provider` — atom id of the provider (`:anthropic`,
      `:claude_code`, `:openrouter`, …).
    * `:cost_profile` — `:free | :subscription_included |
      :subscription_metered | :pay_per_token`. Drives the dominant
      term in `Preference.score/4`.
    * `:subscription` — optional `%{plan: String.t(), monthly_fee:
      Money.t()}` describing the subscription. Used by the dashboard
      to amortize cost across actual token usage. `nil` for
      pay-per-token accounts.
    * `:credentials_status` — `:ready | :missing | :expired`. A purely
      informational field; routing reads `:availability`.
    * `:availability` — `:ready | :degraded | {:rate_limited,
      DateTime.t()} | :unavailable`. Hard filter for `:unavailable`;
      continuous penalty for the others.
    * `:quotas` — optional `%{tokens_used: int, tokens_limit: int,
      period_end: DateTime.t()}`. Drives `quota_pressure_score/1` so
      subscriptions taper toward pay-per-token alternatives as the
      cap is approached.
    * `:account_id` — opaque string identifying which configured
      account this is (Worth uses this when multiple keys for the
      same provider are configured). Surfaced on routes so spend
      attribution is unambiguous.
  """

  @type cost_profile ::
          :free | :subscription_included | :subscription_metered | :pay_per_token

  @type availability ::
          :ready | :degraded | :unavailable | {:rate_limited, DateTime.t()}

  @type credentials_status :: :ready | :missing | :expired

  @type subscription :: %{required(:plan) => String.t(), required(:monthly_fee) => any()}

  @type quotas :: %{
          required(:tokens_used) => non_neg_integer(),
          required(:tokens_limit) => non_neg_integer(),
          required(:period_end) => DateTime.t()
        }

  @type t :: %__MODULE__{
          provider: atom(),
          account_id: String.t(),
          cost_profile: cost_profile(),
          subscription: subscription() | nil,
          credentials_status: credentials_status(),
          availability: availability(),
          quotas: quotas() | nil
        }

  defstruct provider: nil,
            account_id: nil,
            cost_profile: :pay_per_token,
            subscription: nil,
            credentials_status: :ready,
            availability: :ready,
            quotas: nil

  @doc """
  Build a sensible default account for `provider` — used in tests and as
  a fallback when the host did not supply an account in `ctx.metadata`.

  Defaults to `:pay_per_token` + `:ready`, which is the right behaviour
  for someone who pasted in a regular API key and hasn't told us
  anything more.
  """
  @spec default(atom()) :: t()
  def default(provider) when is_atom(provider) do
    %__MODULE__{
      provider: provider,
      account_id: Atom.to_string(provider),
      cost_profile: :pay_per_token,
      availability: :ready,
      credentials_status: :ready
    }
  end

  @doc """
  Look up the account for `provider` in a list of `ProviderAccount` structs,
  falling back to `default/1`. Used by the router to find the matching
  account for each pathway.
  """
  @spec for_provider([t()] | nil, atom()) :: t()
  def for_provider(nil, provider), do: default(provider)
  def for_provider([], provider), do: default(provider)

  def for_provider(accounts, provider) when is_list(accounts) do
    Enum.find(accounts, &(&1.provider == provider)) || default(provider)
  end

  @doc """
  Compute the [0.0..1.0]+ pressure that quota usage adds to scoring.
  Returns 0.0 when there is plenty of headroom; ramps after 70% of the
  cap; hard cliff after 90%. Designed so subscriptions taper toward
  alternative pathways as the weekly cap is approached, rather than
  hard-failing mid-session.
  """
  @spec quota_pressure(t()) :: float()
  def quota_pressure(%__MODULE__{quotas: nil}), do: 0.0

  def quota_pressure(%__MODULE__{quotas: %{tokens_used: u, tokens_limit: l}}) when l > 0 do
    pressure = u / l

    cond do
      pressure < 0.7 -> 0.0
      pressure < 0.9 -> 3.0 * (pressure - 0.7) / 0.2
      true -> 3.0 + 50.0 * min(pressure - 0.9, 1.0)
    end
  end

  def quota_pressure(%__MODULE__{}), do: 0.0
end
