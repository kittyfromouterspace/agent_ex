defmodule Agentic.ModelRouter.Preference do
  @moduledoc """
  Defines model selection preferences and the scoring logic for each.

  User preferences control how the Selector ranks candidate models:

    * `:optimize_price` — prefer cheaper models; only upgrade when
      the analysis demands it (complex tasks, vision, etc.)
    * `:optimize_speed` — prefer faster models; prioritize throughput
      and low latency, willing to spend more

  The preference is combined with an `Analyzer.analysis()` result to
  produce a scoring function used by `Selector.rank/3`.
  """

  @type preference :: :optimize_price | :optimize_speed

  @doc "Parse a preference from user input."
  @spec parse(term()) :: {:ok, preference()} | {:error, term()}
  def parse(:optimize_price), do: {:ok, :optimize_price}
  def parse(:optimize_speed), do: {:ok, :optimize_speed}
  def parse("price"), do: {:ok, :optimize_price}
  def parse("speed"), do: {:ok, :optimize_speed}
  def parse("optimize_price"), do: {:ok, :optimize_price}
  def parse("optimize_speed"), do: {:ok, :optimize_speed}
  def parse(other), do: {:error, {:invalid_preference, other}}

  @doc "Return the default preference."
  @spec default() :: preference()
  def default, do: :optimize_price

  alias Agentic.LLM.Model
  alias Agentic.LLM.ProviderAccount
  alias Agentic.ModelRouter.Analyzer

  @doc """
  Compute a score for a model given a preference and analysis.

  Lower scores are better. The scoring considers:
  - Base cost or speed rating
  - Complexity-appropriate tier matching
  - Capability matching (vision, reasoning, etc.)
  - Penalty for missing required capabilities
  """
  @spec score(Model.t(), preference(), Analyzer.analysis()) :: float()
  def score(model, preference, analysis) do
    base_score = base_score(model, preference)
    complexity_adjustment = complexity_adjustment(model, analysis.complexity, preference)
    capability_penalty = capability_penalty(model, analysis)
    context_adjustment = context_adjustment(model, analysis)

    base_score + complexity_adjustment + capability_penalty + context_adjustment
  end

  defp base_score(model, :optimize_price) do
    case model.cost do
      %{input: input, output: output} ->
        avg = (input + output) / 2

        cond do
          avg == 0.0 -> 0.0
          true -> :math.log(avg + 1) * 5
        end

      _ ->
        5.0
    end
  end

  defp base_score(model, :optimize_speed) do
    cond do
      MapSet.member?(model.capabilities, :free) -> 1.0
      model.tier_hint == :lightweight -> 2.0
      model.tier_hint == :primary -> 4.0
      true -> 6.0
    end
  end

  defp complexity_adjustment(model, :simple, :optimize_price) do
    if model.tier_hint == :lightweight or MapSet.member?(model.capabilities, :free) do
      -2.0
    else
      3.0
    end
  end

  defp complexity_adjustment(model, :simple, :optimize_speed) do
    if model.tier_hint == :lightweight or MapSet.member?(model.capabilities, :free) do
      -1.5
    else
      1.0
    end
  end

  defp complexity_adjustment(_model, :moderate, _preference), do: 0.0

  defp complexity_adjustment(model, :complex, :optimize_price) do
    if model.tier_hint == :primary do
      -3.0
    else
      2.0
    end
  end

  defp complexity_adjustment(model, :complex, :optimize_speed) do
    cond do
      MapSet.member?(model.capabilities, :reasoning) -> -2.0
      model.tier_hint == :primary -> -1.0
      true -> 1.0
    end
  end

  defp capability_penalty(model, analysis) do
    penalty = 0.0

    penalty =
      if analysis.needs_vision and not MapSet.member?(model.capabilities, :vision) do
        penalty + 100.0
      else
        penalty
      end

    penalty =
      if analysis.needs_audio and not MapSet.member?(model.capabilities, :audio) do
        penalty + 100.0
      else
        penalty
      end

    penalty =
      if analysis.needs_reasoning and not MapSet.member?(model.capabilities, :reasoning) do
        penalty + 5.0
      else
        penalty
      end

    required = analysis.required_capabilities || []

    penalty =
      Enum.reduce(required, penalty, fn cap, acc ->
        if cap in [:chat, :tools] and not MapSet.member?(model.capabilities, cap) do
          acc + 100.0
        else
          acc
        end
      end)

    penalty
  end

  defp context_adjustment(model, analysis) do
    if analysis.needs_large_context do
      case model.context_window do
        nil -> 5.0
        cw when cw >= 100_000 -> -10.0
        cw when cw >= 50_000 -> -3.0
        _ -> 5.0
      end
    else
      0.0
    end
  end

  # ----- multi-pathway scoring (account-aware) -----

  @doc """
  Score a `(model, account)` pathway pair within a canonical group.

  Used by `Agentic.ModelRouter` in manual mode after `Catalog.by_canonical/1`
  has grouped pathways. Lower is better.

  The account contributes three terms on top of the base price/speed
  preference:

    * `cost_profile_score/3` — strongly prefers `:free >
      :subscription_included > :subscription_metered > :pay_per_token`
      under `:optimize_price`; mild speed bonus for subscriptions
      under `:optimize_speed`.
    * `Agentic.LLM.ProviderAccount.quota_pressure/1` — taper away from
      a subscription as it approaches its weekly cap (0 at <70%, ramp
      through 90%, cliff above).
    * `availability_score/1` — `:ready` adds 0; `:degraded` +2;
      `{:rate_limited, _}` +8; `:unavailable` is filtered upstream.

  Distinct from `score/3` (the analyzer-driven auto-mode scorer) which
  takes an `Analyzer.analysis()` instead of an account.
  """
  @spec score_pathway(Model.t(), ProviderAccount.t(), preference()) :: float()
  def score_pathway(%Model{} = model, %ProviderAccount{} = account, preference) do
    base_score(model, preference) +
      cost_profile_score(model, account, preference) +
      ProviderAccount.quota_pressure(account) +
      availability_score(account)
  end

  @doc false
  def cost_profile_score(model, %ProviderAccount{cost_profile: profile}, preference) do
    case {profile, preference} do
      {:free, :optimize_price} -> -10.0
      {:subscription_included, :optimize_price} -> -5.0
      {:subscription_metered, :optimize_price} -> 0.0
      {:pay_per_token, :optimize_price} -> base_score(model, :optimize_price)
      {:free, :optimize_speed} -> 0.0
      {:subscription_included, :optimize_speed} -> -2.0
      {:subscription_metered, :optimize_speed} -> -1.0
      {:pay_per_token, :optimize_speed} -> 0.0
    end
  end

  @doc false
  def availability_score(%ProviderAccount{availability: :ready}), do: 0.0
  def availability_score(%ProviderAccount{availability: :degraded}), do: 2.0
  def availability_score(%ProviderAccount{availability: {:rate_limited, _until}}), do: 8.0
  # :unavailable should have been filtered out before scoring; if it
  # leaks through give it an enormous penalty so the router still
  # picks a different pathway.
  def availability_score(%ProviderAccount{availability: :unavailable}), do: 1_000.0
end
