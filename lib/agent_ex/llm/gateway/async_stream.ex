defmodule AgentEx.LLM.Gateway.AsyncStream do
  @moduledoc false
  defstruct [:async, :on_chunk, :on_done]

  defimpl Enumerable do
    def count(_async), do: {:error, __MODULE__}
    def member?(_async, _value), do: {:error, __MODULE__}
    def slice(_async), do: {:error, __MODULE__}

    def reduce(async, acc, fun) do
      wrapped_fun = fn chunk, inner_acc ->
        if async.on_chunk, do: async.on_chunk.()
        fun.(chunk, inner_acc)
      end

      result = Enumerable.reduce(async.async, acc, wrapped_fun)
      if async.on_done, do: async.on_done.()
      result
    end
  end
end
