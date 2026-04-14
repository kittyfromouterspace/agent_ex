defmodule AgentEx.Strategy.Registry do
  @moduledoc """
  Process registry for strategy modules.

  Strategies are registered by their `id/0` callback. The Default
  strategy is always pre-registered.
  """

  use Agent

  def start_link(_opts) do
    Agent.start_link(
      fn -> %{default: AgentEx.Strategy.Default} end,
      name: __MODULE__
    )
  end

  @doc "Register a strategy module."
  @spec register(module()) :: :ok
  def register(mod) when is_atom(mod) do
    Agent.update(__MODULE__, &Map.put(&1, mod.id(), mod))
  end

  @doc "Fetch a strategy module by id, or nil if not registered."
  @spec fetch(atom()) :: module() | nil
  def fetch(id) do
    Agent.get(__MODULE__, &Map.get(&1, id))
  end

  @doc "Fetch a strategy module by id, raising if not found."
  @spec fetch!(atom()) :: module()
  def fetch!(id) do
    case fetch(id) do
      nil -> raise "Strategy not registered: #{inspect(id)}"
      mod -> mod
    end
  end

  @doc "Return all registered strategies as a map of id -> module."
  @spec all() :: %{atom() => module()}
  def all do
    Agent.get(__MODULE__, & &1)
  end
end
