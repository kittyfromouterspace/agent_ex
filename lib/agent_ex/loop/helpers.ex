defmodule AgentEx.Loop.Helpers do
  @moduledoc """
  Shared utility functions for pipeline stages.
  """

  alias AgentEx.Loop.Context

  @doc "Extract plain text from a content block list."
  @spec extract_text(term()) :: String.t()
  def extract_text(content) when is_list(content) do
    content
    |> Enum.filter(&(&1["type"] == "text"))
    |> Enum.map_join("", &(&1["text"] || ""))
  end

  def extract_text(content) when is_binary(content), do: content
  def extract_text(_), do: ""

  @doc "Extract tool_use blocks from a content block list."
  @spec extract_tool_calls(term()) :: [map()]
  def extract_tool_calls(content) when is_list(content) do
    Enum.filter(content, &(&1["type"] == "tool_use"))
  end

  def extract_tool_calls(_), do: []

  @doc "Build a result map from a context struct."
  @spec result_from_context(Context.t()) :: map()
  def result_from_context(%Context{} = ctx) do
    %{
      text: ctx.accumulated_text,
      cost: ctx.total_cost,
      tokens: ctx.total_tokens,
      steps: ctx.turns_used
    }
  end

  @doc "Join two text fragments with a double newline separator."
  @spec join_text(String.t(), String.t()) :: String.t()
  def join_text("", text), do: text
  def join_text(acc, ""), do: acc
  def join_text(acc, text), do: acc <> "\n\n" <> text
end
