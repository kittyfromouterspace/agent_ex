defmodule AgentEx.Concurrency.SemaphoreTest do
  use ExUnit.Case, async: true

  alias AgentEx.Concurrency.Semaphore

  describe "basic operations" do
    test "acquire and release within limit" do
      {:ok, sem} = Semaphore.start_link(limit: 3)

      assert :ok = Semaphore.acquire(sem)
      assert :ok = Semaphore.release(sem)
    end

    test "reports correct limit" do
      {:ok, sem} = Semaphore.start_link(limit: 5)
      assert Semaphore.limit(sem) == 5
    end

    test "reports stats" do
      {:ok, sem} = Semaphore.start_link(limit: 2)

      Semaphore.acquire(sem)
      Semaphore.release(sem)

      stats = Semaphore.stats(sem)
      assert stats.total_acquired >= 1
      assert stats.total_released >= 1
      assert stats.limit == 2
    end
  end

  describe "concurrency limit enforcement" do
    test "blocks when limit reached" do
      {:ok, sem} = Semaphore.start_link(limit: 1)

      assert :ok = Semaphore.acquire(sem)

      test_pid = self()

      spawn(fn ->
        :ok = Semaphore.acquire(sem, 1000)
        send(test_pid, :acquired)
        Semaphore.release(sem)
      end)

      refute_received :acquired

      Semaphore.release(sem)

      assert_receive :acquired, 500
    end
  end

  describe "automatic release on process crash" do
    test "releases permit when holding process crashes" do
      {:ok, sem} = Semaphore.start_link(limit: 1)

      test_pid = self()

      crashing_pid =
        spawn(fn ->
          Semaphore.acquire(sem)
          send(test_pid, :ready)
          Process.sleep(50)
          raise "intentional crash"
        end)

      assert_receive :ready, 500
      Process.exit(crashing_pid, :kill)
      Process.sleep(100)

      stats = Semaphore.stats(sem)
      assert stats.available >= 1
    end
  end

  describe "with_permit/2" do
    test "auto-releases permit after function completes" do
      {:ok, sem} = Semaphore.start_link(limit: 1)

      result = Semaphore.with_permit(sem, fn -> :hello end)
      assert result == :hello

      stats = Semaphore.stats(sem)
      assert stats.available == 1
    end

    test "auto-releases permit on exception" do
      {:ok, sem} = Semaphore.start_link(limit: 1)

      try do
        Semaphore.with_permit(sem, fn -> raise "boom" end)
      rescue
        _ -> :ok
      end

      stats = Semaphore.stats(sem)
      assert stats.available == 1
    end
  end
end
