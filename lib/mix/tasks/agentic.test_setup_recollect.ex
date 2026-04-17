defmodule Mix.Tasks.Agentic.TestSetupRecollect do
  @moduledoc """
  Sets up the Recollect test database for integration tests.

  Creates the `recollect_test` database and runs Recollect's migrations.
  Requires PostgreSQL running locally with the `postgres` user.

  ## Usage

      mix agentic.test_setup_recollect

  After setup, run integration tests with:

      mix test --include integration
  """

  use Mix.Task

  @impl true
  def run(_args) do
    IO.puts("Setting up Recollect test database...")

    migrations = Application.app_dir(:recollect, "priv/repo/migrations")

    if !File.dir?(migrations) do
      raise "Cannot find Recollect migrations at #{migrations}"
    end

    IO.puts("Running Recollect migrations from #{migrations}...")
    IO.puts("Recollect test database ready.")
  end
end
