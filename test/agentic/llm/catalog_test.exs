defmodule Agentic.LLM.CatalogTest do
  use ExUnit.Case

  alias Agentic.LLM.{Catalog, Model}

  setup do
    on_exit(fn ->
      File.rm_rf(Path.expand("~/.worth/catalog.json"))
    end)

    :ok
  end

  describe "Catalog.find/1" do
    test "finds models by provider" do
      models = Catalog.find(provider: :anthropic)
      assert length(models) > 0
      assert Enum.all?(models, &(&1.provider == :anthropic))
    end

    test "finds models by tier" do
      models = Catalog.find(tier: :primary)
      assert length(models) > 0
      assert Enum.all?(models, &(&1.tier_hint == :primary))
    end

    test "finds models by capability tag" do
      models = Catalog.find(has: :tools)
      assert length(models) > 0
      assert Enum.all?(models, &MapSet.member?(&1.capabilities, :tools))
    end

    test "finds models by multiple capability tags" do
      models = Catalog.find(has: [:chat, :tools])
      assert length(models) > 0

      assert Enum.all?(models, fn m ->
               MapSet.member?(m.capabilities, :chat) and
                 MapSet.member?(m.capabilities, :tools)
             end)
    end

    test "returns empty list for non-existent provider" do
      models = Catalog.find(provider: :nonexistent_provider)
      assert models == []
    end
  end

  describe "Catalog.for_provider/1" do
    test "returns models for anthropic" do
      models = Catalog.for_provider(:anthropic)
      assert length(models) >= 3

      ids = Enum.map(models, & &1.id)
      assert "claude-sonnet-4-20250514" in ids
    end

    test "returns models for groq" do
      models = Catalog.for_provider(:groq)
      assert length(models) >= 2
    end
  end

  describe "Catalog.lookup/2" do
    test "finds a specific model" do
      model = Catalog.lookup(:anthropic, "claude-sonnet-4-20250514")
      assert %Model{} = model
      assert model.provider == :anthropic
      assert model.label == "Claude Sonnet 4"
    end

    test "returns nil for unknown model" do
      assert Catalog.lookup(:anthropic, "nonexistent") == nil
    end
  end

  describe "Catalog.all/0" do
    test "returns all models from all providers" do
      models = Catalog.all()
      assert length(models) > 0

      providers =
        models
        |> Enum.map(& &1.provider)
        |> Enum.uniq()

      assert :anthropic in providers
    end
  end

  describe "Catalog.info/0" do
    test "returns catalog metadata" do
      info = Catalog.info()
      assert info.model_count > 0
      assert is_map(info.providers)
    end
  end
end
