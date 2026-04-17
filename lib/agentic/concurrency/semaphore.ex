defmodule Agentic.Concurrency.Semaphore do
  @moduledoc """
  Bounded concurrency semaphore using a GenServer.

  Ported from SCE. Limits the number of concurrent tasks that can hold permits.
  Automatically releases permits when the holding process crashes.

  ## Usage

      {:ok, sem} = Semaphore.start_link(limit: 5)
      :ok = Semaphore.acquire(sem)
      # do work
      :ok = Semaphore.release(sem)

  Or with automatic release:

      Semaphore.with_permit(sem, fn ->
        # do work — permit auto-released on return or crash
      end)
  """

  use GenServer

  defstruct [:limit, :available, :queue, :monitors, :stats]

  @type t :: %__MODULE__{
          limit: pos_integer(),
          available: non_neg_integer(),
          queue: :queue.queue(),
          monitors: %{reference() => pid()},
          stats: %{total_acquired: non_neg_integer(), total_released: non_neg_integer()}
        }

  @doc "Start a semaphore with the given concurrency limit."
  def start_link(opts) do
    limit = Keyword.fetch!(opts, :limit)
    GenServer.start_link(__MODULE__, limit, Keyword.take(opts, [:name]))
  end

  @doc "Acquire a permit. Blocks if none available. Returns `:ok`. Times out after 5 seconds by default."
  def acquire(sem, timeout \\ 5000) do
    GenServer.call(sem, {:acquire, self()}, timeout)
  end

  @doc "Release a permit. Returns `:ok`."
  def release(sem) do
    GenServer.cast(sem, {:release, self()})
    :ok
  end

  @doc "Execute a function with an automatically managed permit."
  def with_permit(sem, fun) do
    case acquire(sem) do
      :ok ->
        try do
          fun.()
        after
          release(sem)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Get current stats."
  def stats(sem) do
    GenServer.call(sem, :stats)
  end

  @doc "Get the concurrency limit."
  def limit(sem) do
    GenServer.call(sem, :limit)
  end

  @impl true
  def init(limit) do
    {:ok,
     %__MODULE__{
       limit: limit,
       available: limit,
       queue: :queue.new(),
       monitors: %{},
       stats: %{total_acquired: 0, total_released: 0}
     }}
  end

  @impl true
  def handle_call({:acquire, pid}, from, state) do
    if state.available > 0 do
      ref = Process.monitor(pid)

      state = %{
        state
        | available: state.available - 1,
          monitors: Map.put(state.monitors, ref, pid)
      }

      state = update_stats(state, :acquired)
      {:reply, :ok, state}
    else
      state = %{state | queue: :queue.in(from, state.queue)}
      {:noreply, state}
    end
  end

  def handle_call(:stats, _from, state) do
    info = %{
      limit: state.limit,
      available: state.available,
      waiting: :queue.len(state.queue),
      total_acquired: state.stats.total_acquired,
      total_released: state.stats.total_released
    }

    {:reply, info, state}
  end

  def handle_call(:limit, _from, state) do
    {:reply, state.limit, state}
  end

  @impl true
  def handle_cast({:release, _pid}, state) do
    state = do_release(state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.monitors, ref) do
      {nil, _monitors} ->
        {:noreply, state}

      {_pid, monitors} ->
        state = %{state | monitors: monitors}
        state = do_release(state)
        {:noreply, state}
    end
  end

  defp do_release(state) do
    state = %{state | available: state.available + 1}
    state = update_stats(state, :released)

    case :queue.out(state.queue) do
      {{:value, {pid, _tag} = from}, new_queue} ->
        GenServer.reply(from, :ok)
        ref = Process.monitor(pid)

        %{
          state
          | available: state.available - 1,
            queue: new_queue,
            monitors: Map.put(state.monitors, ref, pid)
        }

      {:empty, _queue} ->
        state
    end
  end

  defp update_stats(state, :acquired) do
    put_in(state.stats.total_acquired, state.stats.total_acquired + 1)
  end

  defp update_stats(state, :released) do
    put_in(state.stats.total_released, state.stats.total_released + 1)
  end
end
