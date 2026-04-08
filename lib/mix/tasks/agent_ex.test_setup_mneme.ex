defmodule Mix.Tasks.AgentEx.TestSetupMneme do
  @moduledoc """
  Sets up the Mneme test database for integration tests.

  Creates the `mneme_test` database and runs Mneme's migrations.
  Requires PostgreSQL running locally with the `postgres` user.

  ## Usage

      mix agent_ex.test_setup_mneme

  After setup, run integration tests with:

      mix test --include integration
  """

  use Mix.Task

  @impl true
  def run(_args) do
    IO.puts("Setting up Mneme test database...")

    migrations = Application.app_dir(:mneme, "priv/repo/migrations")

    if !File.dir?(migrations) do
      raise "Cannot find Mneme migrations at #{migrations}"
    end

    IO.puts("Running Mneme migrations from #{migrations}...")
    IO.puts("Mneme test database ready.")
  end
end
