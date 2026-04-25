defmodule Mix.Tasks.Agentic.Routes do
  @moduledoc """
  Inspect multi-pathway model routing decisions.

  ## Usage

      mix agentic.routes
      mix agentic.routes --canonical claude-sonnet-4
      mix agentic.routes --tier primary
      mix agentic.routes --canonical claude-sonnet-4 --preference optimize_speed

  When `--canonical` is given, prints every pathway model that maps to
  that canonical id along with its score breakdown (cost_profile,
  quota_pressure, availability) under the chosen preference.

  Without `--canonical`, prints the top route for each canonical group
  in the chosen tier.
  """

  use Mix.Task

  alias Agentic.LLM.{Canonical, Catalog, ProviderAccount}
  alias Agentic.ModelRouter.Preference

  @shortdoc "Inspect multi-pathway model routing decisions"
  @switches [canonical: :string, tier: :string, preference: :string]

  @impl Mix.Task
  def run(argv) do
    {opts, _rest, _invalid} = OptionParser.parse(argv, strict: @switches)

    Mix.Task.run("app.start")

    canonical = opts[:canonical]
    tier = (opts[:tier] || "primary") |> String.to_atom()
    preference = (opts[:preference] || "optimize_price") |> String.to_atom()

    cond do
      canonical -> show_canonical_group(canonical, preference)
      true -> show_tier(tier, preference)
    end
  end

  defp show_canonical_group(canonical, preference) do
    Mix.shell().info("Canonical: #{canonical}")
    Mix.shell().info("Preference: #{preference}\n")

    pathways = Catalog.find(canonical: canonical)

    if pathways == [] do
      Mix.shell().info("(no pathways found)")
    else
      Enum.each(pathways, fn model ->
        account = ProviderAccount.default(model.provider)
        score = Preference.score_pathway(model, account, preference)
        cp_score = Preference.cost_profile_score(model, account, preference)
        avail_score = Preference.availability_score(account)
        quota_score = ProviderAccount.quota_pressure(account)

        Mix.shell().info("  #{model.provider} / #{model.id}")
        Mix.shell().info("    label: #{model.label || "—"}")

        Mix.shell().info(
          "    score: #{format_float(score)} = base + cost(#{format_float(cp_score)}) + quota(#{format_float(quota_score)}) + availability(#{format_float(avail_score)})"
        )

        Mix.shell().info("    cost_profile: #{account.cost_profile}")
        Mix.shell().info("    availability: #{inspect(account.availability)}")
        Mix.shell().info("")
      end)
    end
  end

  defp show_tier(tier, _preference) do
    Mix.shell().info("Tier: #{tier}\n")

    case Agentic.ModelRouter.resolve_all(tier) do
      {:ok, routes} ->
        Enum.each(routes, fn route ->
          Mix.shell().info("  #{route.canonical_model_id}")
          Mix.shell().info("    chosen: #{route.provider_name} / #{route.model_id}")
          Mix.shell().info("    cost_profile: #{route.cost_profile}")
          Mix.shell().info("    pathway_score: #{format_float(route.pathway_score)}")
          Mix.shell().info("    priority: #{route.priority}  status: #{route.status}")

          if route.pathway_fallbacks != [] do
            fallback_summary =
              route.pathway_fallbacks
              |> Enum.map_join(", ", fn f -> "#{f.provider_name}(#{format_float(f.score)})" end)

            Mix.shell().info("    fallbacks: #{fallback_summary}")
          end

          Mix.shell().info("")
        end)

      {:error, reason} ->
        Mix.shell().error("error: #{inspect(reason)}")
    end

    info = Canonical.info()

    Mix.shell().info(
      "models.dev: #{info.model_count} entries, last_fetch=#{inspect(info.last_fetch)}"
    )
  end

  defp format_float(n) when is_float(n), do: Float.round(n, 2)
  defp format_float(n) when is_integer(n), do: n * 1.0
  defp format_float(_), do: "?"
end
