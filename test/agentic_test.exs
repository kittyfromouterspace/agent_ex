defmodule AgenticTest do
  use ExUnit.Case

  test "run/1 requires prompt, workspace, and callbacks" do
    assert_raise KeyError, ~r/key :prompt not found/, fn ->
      Agentic.run([])
    end
  end
end
