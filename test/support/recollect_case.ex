defmodule Agentic.RecollectCase do
  @moduledoc """
  Test case for Recollect-backed knowledge tests.

  Sets up Ecto SQL Sandbox for each test. Only runs when Recollect TestRepo
  is available (Postgres running, migrations applied).
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Agentic.RecollectCase
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Recollect.TestRepo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  def scope_id, do: Ecto.UUID.generate()
  def owner_id, do: Ecto.UUID.generate()
end
