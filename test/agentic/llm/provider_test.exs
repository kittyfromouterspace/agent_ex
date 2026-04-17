defmodule Agentic.LLM.ProviderTest do
  use ExUnit.Case, async: true

  alias Agentic.LLM.{Credentials, Model}

  describe "Agentic.LLM.Provider.Anthropic" do
    test "id/0" do
      assert Agentic.LLM.Provider.Anthropic.id() == :anthropic
    end

    test "label/0" do
      assert Agentic.LLM.Provider.Anthropic.label() == "Anthropic"
    end

    test "transport/0" do
      assert Agentic.LLM.Provider.Anthropic.transport() == Agentic.LLM.Transport.AnthropicMessages
    end

    test "env_vars/0" do
      assert Agentic.LLM.Provider.Anthropic.env_vars() == ["ANTHROPIC_API_KEY"]
    end

    test "default_models/0 returns models with pricing" do
      models = Agentic.LLM.Provider.Anthropic.default_models()

      assert length(models) == 3

      for model <- models do
        assert %Model{} = model
        assert model.provider == :anthropic
        assert model.cost.input > 0
        assert model.cost.output > 0
        assert MapSet.member?(model.capabilities, :chat)
        assert MapSet.member?(model.capabilities, :tools)
      end
    end

    test "supports/0" do
      supports = Agentic.LLM.Provider.Anthropic.supports()
      assert MapSet.member?(supports, :chat)
      assert MapSet.member?(supports, :tools)
      refute MapSet.member?(supports, :embeddings)
    end

    test "fetch_catalog/1 returns :not_supported" do
      assert Agentic.LLM.Provider.Anthropic.fetch_catalog(%Credentials{}) == :not_supported
    end
  end

  describe "Agentic.LLM.Provider.OpenAI" do
    test "id/0" do
      assert Agentic.LLM.Provider.OpenAI.id() == :openai
    end

    test "default_models/0 includes embedding model" do
      models = Agentic.LLM.Provider.OpenAI.default_models()
      embeddings = Enum.filter(models, &MapSet.member?(&1.capabilities, :embeddings))
      assert length(embeddings) == 1
      assert hd(embeddings).id == "text-embedding-3-small"
    end

    test "supports/0 includes embeddings" do
      supports = Agentic.LLM.Provider.OpenAI.supports()
      assert MapSet.member?(supports, :embeddings)
    end
  end

  describe "Agentic.LLM.Provider.OpenRouter" do
    test "id/0" do
      assert Agentic.LLM.Provider.OpenRouter.id() == :openrouter
    end

    test "transport/0 uses OpenAI compat" do
      assert Agentic.LLM.Provider.OpenRouter.transport() ==
               Agentic.LLM.Transport.OpenAIChatCompletions
    end

    test "request_headers/1 includes analytics headers" do
      headers = Agentic.LLM.Provider.OpenRouter.request_headers(%Credentials{})
      assert Enum.any?(headers, fn {k, _} -> k == "HTTP-Referer" end)
      assert Enum.any?(headers, fn {k, _} -> k == "X-Title" end)
    end

    test "fetch_catalog/1 without api key returns :not_supported" do
      assert Agentic.LLM.Provider.OpenRouter.fetch_catalog(%Credentials{}) == :not_supported
    end
  end

  describe "Agentic.LLM.Provider.Groq" do
    test "id/0" do
      assert Agentic.LLM.Provider.Groq.id() == :groq
    end

    test "label/0" do
      assert Agentic.LLM.Provider.Groq.label() == "Groq"
    end

    test "default_base_url/0" do
      assert Agentic.LLM.Provider.Groq.default_base_url() == "https://api.groq.com/openai/v1"
    end

    test "default_models/0 returns models" do
      models = Agentic.LLM.Provider.Groq.default_models()
      assert length(models) == 2

      ids = Enum.map(models, & &1.id)
      assert "llama-3.3-70b-versatile" in ids
      assert "llama-3.1-8b-instant" in ids
    end

    test "classify_http_error/3 — model_is_deactivated" do
      body = %{"error" => %{"message" => "model_is_deactivated"}}
      result = Agentic.LLM.Provider.Groq.classify_http_error(400, body, [])
      assert {:model_not_found, nil} = result
    end

    test "classify_http_error/3 — default for unknown" do
      assert Agentic.LLM.Provider.Groq.classify_http_error(429, "rate limited", []) == :default
    end
  end

  describe "Agentic.LLM.Credentials" do
    test "resolve/1 returns :not_configured for unconfigured provider" do
      original = System.get_env("GROQ_API_KEY")
      System.delete_env("GROQ_API_KEY")

      try do
        assert :not_configured = Credentials.resolve(Agentic.LLM.Provider.Groq)
      after
        if original, do: System.put_env("GROQ_API_KEY", original)
      end
    end

    test "resolve/1 returns credentials when env var is set" do
      original = System.get_env("GROQ_API_KEY")
      System.put_env("GROQ_API_KEY", "test-key-123")

      try do
        assert {:ok, %Credentials{api_key: "test-key-123"}} =
                 Credentials.resolve(Agentic.LLM.Provider.Groq)
      after
        if original do
          System.put_env("GROQ_API_KEY", original)
        else
          System.delete_env("GROQ_API_KEY")
        end
      end
    end

    test "available?/1 returns false for unconfigured provider" do
      original = System.get_env("GROQ_API_KEY")
      System.delete_env("GROQ_API_KEY")

      try do
        refute Credentials.available?(Agentic.LLM.Provider.Groq)
      after
        if original, do: System.put_env("GROQ_API_KEY", original)
      end
    end
  end
end
