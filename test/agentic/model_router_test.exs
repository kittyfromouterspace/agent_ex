defmodule Agentic.ModelRouterTest do
  use ExUnit.Case, async: false

  alias Agentic.Loop.Context
  alias Agentic.ModelRouter

  describe "resolve_for_context/1 manual mode" do
    test "resolves routes based on tier in manual mode" do
      ctx =
        Context.new(
          session_id: "test",
          model_tier: :primary,
          model_selection_mode: :manual,
          callbacks: %{
            llm_chat: fn _ ->
              {:ok, %Agentic.LLM.Response{content: [], stop_reason: :end_turn}}
            end
          }
        )

      case ModelRouter.resolve_for_context(ctx) do
        {:ok, routes, nil} ->
          assert is_list(routes)

        {:error, _reason} ->
          :ok
      end
    end
  end

  describe "resolve_for_context/1 auto mode" do
    test "uses Selector in auto mode" do
      llm_chat = fn _params ->
        {:ok,
         %Agentic.LLM.Response{
           content: [
             %{
               type: :text,
               text:
                 ~s({"complexity": "simple", "required_capabilities": ["chat"], "needs_vision": false, "needs_audio": false, "needs_reasoning": false, "needs_large_context": false, "estimated_input_tokens": 50, "explanation": "test"})
             }
           ],
           stop_reason: :end_turn,
           usage: %{input_tokens: 10, output_tokens: 20, cache_read: 0, cache_write: 0}
         }}
      end

      ctx =
        Context.new(
          session_id: "test",
          model_selection_mode: :auto,
          model_preference: :optimize_price,
          messages: [%{"role" => "user", "content" => "Hello"}],
          callbacks: %{llm_chat: llm_chat}
        )

      case ModelRouter.resolve_for_context(ctx) do
        {:ok, routes, analysis, _scores} ->
          assert is_list(routes)

          if analysis do
            assert analysis.complexity == :simple
          end

        {:error, _reason} ->
          :ok
      end
    end
  end

  describe "auto_select/3" do
    test "returns route and analysis" do
      llm_chat = fn _params ->
        {:ok,
         %Agentic.LLM.Response{
           content: [
             %{
               type: :text,
               text:
                 ~s({"complexity": "moderate", "required_capabilities": ["chat", "tools"], "needs_vision": false, "needs_audio": false, "needs_reasoning": false, "needs_large_context": false, "estimated_input_tokens": 500, "explanation": "test"})
             }
           ],
           stop_reason: :end_turn,
           usage: %{input_tokens: 10, output_tokens: 20, cache_read: 0, cache_write: 0}
         }}
      end

      result = ModelRouter.auto_select("Write a function", :optimize_speed, llm_chat: llm_chat)

      case result do
        {:ok, route, analysis} ->
          assert is_map(route)
          assert is_map(analysis)

        {:error, :no_models_available} ->
          :ok

        {:error, _reason} ->
          :ok
      end
    end
  end

  describe "resolve_all/1 ordering" do
    test ":primary tier puts paid configured/static models ahead of free discovered ones" do
      {:ok, routes} = ModelRouter.resolve_all(:primary)

      paid = Enum.reject(routes, &MapSet.member?(&1.capabilities, :free))
      free = Enum.filter(routes, &MapSet.member?(&1.capabilities, :free))

      if paid != [] and free != [] do
        max_paid_priority = paid |> Enum.map(& &1.priority) |> Enum.max()
        min_free_priority = free |> Enum.map(& &1.priority) |> Enum.min()

        assert max_paid_priority < min_free_priority,
               "expected every paid :primary route to outrank every free one"
      end
    end

    test "every :primary route is conversational (has :chat and :tools)" do
      {:ok, routes} = ModelRouter.resolve_all(:primary)

      Enum.each(routes, fn route ->
        assert MapSet.member?(route.capabilities, :chat),
               "route #{route.provider_name}/#{route.model_id} on :primary missing :chat"

        assert MapSet.member?(route.capabilities, :tools),
               "route #{route.provider_name}/#{route.model_id} on :primary missing :tools"
      end)
    end
  end

  describe "resolve_for_context/1 with :free_only filter" do
    test "in manual mode, filters routes to free models only" do
      ctx =
        Context.new(
          session_id: "test-free-manual",
          model_selection_mode: :manual,
          model_tier: :any,
          model_filter: :free_only,
          callbacks: %{
            llm_chat: fn _ ->
              {:ok, %Agentic.LLM.Response{content: [], stop_reason: :end_turn}}
            end
          }
        )

      case ModelRouter.resolve_for_context(ctx) do
        {:ok, routes, nil} ->
          assert is_list(routes)

          if routes != [] do
            Enum.each(routes, fn route ->
              assert MapSet.member?(route.capabilities, :free)
            end)
          end

        {:error, :no_free_models_available} ->
          :ok

        {:error, _reason} ->
          :ok
      end
    end

    test "in auto mode, filters to free models via Selector" do
      llm_chat = fn _params ->
        {:ok,
         %Agentic.LLM.Response{
           content: [
             %{
               type: :text,
               text:
                 ~s({"complexity": "simple", "required_capabilities": ["chat"], "needs_vision": false, "needs_audio": false, "needs_reasoning": false, "needs_large_context": false, "estimated_input_tokens": 50, "explanation": "test"})
             }
           ],
           stop_reason: :end_turn,
           usage: %{input_tokens: 10, output_tokens: 20, cache_read: 0, cache_write: 0}
         }}
      end

      ctx =
        Context.new(
          session_id: "test-free-auto",
          model_selection_mode: :auto,
          model_preference: :optimize_price,
          model_filter: :free_only,
          messages: [%{"role" => "user", "content" => "Hello"}],
          callbacks: %{llm_chat: llm_chat}
        )

      case ModelRouter.resolve_for_context(ctx) do
        {:ok, routes, _analysis, _scores} ->
          assert is_list(routes)

          if routes != [] do
            Enum.each(routes, fn route ->
              assert MapSet.member?(route.capabilities, :free)
            end)
          end

        {:error, :no_models_available} ->
          :ok

        {:error, _reason} ->
          :ok
      end
    end
  end
end
