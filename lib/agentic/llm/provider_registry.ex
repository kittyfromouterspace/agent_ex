defmodule Agentic.LLM.ProviderRegistry do
  @moduledoc """
  Hybrid provider registration: compile-time list from
  `config :agentic, providers: [...]`, runtime `enable/1` and
  `disable/1` calls.

  Disabled state persists to the host's config via an optional
  callback (worth uses `Worth.Config`).

  ## Boot sequence

  1. Reads `Agentic.Config.providers/0` for the compile-time list.
  2. Marks providers as `:enabled` unless previously disabled.
  3. Exposes `list/0`, `enabled/0`, `enabled?/1`, `get/1`.
  """

  use GenServer

  require Logger

  @table :agentic_providers

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "List all registered providers (enabled and disabled)."
  def list do
    @table
    |> :ets.match_object({:_, :_, :_})
    |> Enum.map(fn {id, module, status} -> %{id: id, module: module, status: status} end)
  end

  @doc "List only enabled providers."
  def enabled do
    Enum.filter(list(), &(&1.status == :enabled))
  end

  @doc "Check if a specific provider is enabled."
  def enabled?(provider_id) when is_atom(provider_id) do
    case :ets.lookup(@table, provider_id) do
      [{_, _, :enabled}] -> true
      _ -> false
    end
  end

  @doc "Get the module for a provider id. Returns nil if not registered."
  def get(provider_id) when is_atom(provider_id) do
    case :ets.lookup(@table, provider_id) do
      [{_, module, status}] when status == :enabled -> module
      _ -> nil
    end
  end

  def get(provider_name) when is_binary(provider_name) do
    atom = safe_to_atom(provider_name)
    if atom, do: get(atom)
  end

  defp safe_to_atom(name) when is_binary(name) do
    String.to_existing_atom(name)
  rescue
    ArgumentError -> nil
  end

  @doc "Enable a provider by id."
  def enable(provider_id) when is_atom(provider_id) do
    GenServer.call(__MODULE__, {:enable, provider_id})
  end

  @doc "Disable a provider by id."
  def disable(provider_id) when is_atom(provider_id) do
    GenServer.call(__MODULE__, {:disable, provider_id})
  end

  @doc "Register a provider module at runtime."
  def register(module) when is_atom(module) do
    GenServer.call(__MODULE__, {:register, module})
  end

  # --- GenServer callbacks ---

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])

    disabled_ids = load_disabled_set()

    for module <- Agentic.Config.providers() do
      id = module.id()
      status = if id in disabled_ids, do: :disabled, else: :enabled
      :ets.insert(@table, {id, module, status})

      Logger.debug("Agentic.LLM.ProviderRegistry: #{id} -> #{module} (#{status})")
    end

    {:ok, %{disabled_ids: disabled_ids}}
  end

  @impl true
  def handle_call({:enable, provider_id}, _from, state) do
    case :ets.lookup(@table, provider_id) do
      [{_, module, _}] ->
        :ets.insert(@table, {provider_id, module, :enabled})
        new_disabled = List.delete(state.disabled_ids, provider_id)
        persist_disabled(new_disabled)
        {:reply, :ok, %{state | disabled_ids: new_disabled}}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:disable, provider_id}, _from, state) do
    case :ets.lookup(@table, provider_id) do
      [{_, module, _}] ->
        :ets.insert(@table, {provider_id, module, :disabled})
        new_disabled = [provider_id | List.delete(state.disabled_ids, provider_id)]
        persist_disabled(new_disabled)
        {:reply, :ok, %{state | disabled_ids: new_disabled}}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:register, module}, _from, state) do
    id = module.id()
    :ets.insert(@table, {id, module, :enabled})
    {:reply, :ok, state}
  end

  defp load_disabled_set do
    case Application.get_env(:agentic, :disabled_providers) do
      list when is_list(list) -> list
      _ -> []
    end
  end

  defp persist_disabled(disabled_ids) do
    Application.put_env(:agentic, :disabled_providers, disabled_ids)

    persist_to_host(disabled_ids)
  end

  defp persist_to_host(list) do
    case Code.ensure_loaded(Worth.Config) do
      {:module, mod} ->
        if function_exported?(mod, :update, 2) do
          mod.update(:disabled_providers, list)
        end

      {:error, _} ->
        :ok
    end
  rescue
    _ -> :ok
  end
end
