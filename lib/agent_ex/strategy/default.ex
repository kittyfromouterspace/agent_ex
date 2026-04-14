defmodule AgentEx.Strategy.Default do
  @moduledoc """
  Identity strategy. Passes opts through unchanged, matching current
  `AgentEx.run/1` behavior exactly.
  """

  @behaviour AgentEx.Strategy

  @impl true
  def id, do: :default

  @impl true
  def display_name, do: "Default"

  @impl true
  def description, do: "Passes opts through unchanged. Matches current AgentEx.run behavior."

  @impl true
  def init(_opts), do: {:ok, nil}

  @impl true
  def prepare_run(opts, _state), do: {:ok, opts, nil}

  @impl true
  def handle_result({:ok, result}, _opts, _state), do: {:done, result, nil}
  def handle_result({:error, reason}, _opts, _state), do: {:error, reason}

  @impl true
  def handle_event(_event, state), do: {:ok, state}
end
