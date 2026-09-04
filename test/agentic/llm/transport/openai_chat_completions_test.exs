defmodule Agentic.LLM.Transport.OpenAIChatCompletionsTest do
  @moduledoc """
  The canonical-blocks → OpenAI wire transform. Regression cover for the
  marker-spam bug (2026-08-20/24): tool_use blocks flattened to the literal
  text "[tool_use name]" taught models to emit text markers on every
  OpenRouter failover run.
  """

  use ExUnit.Case, async: true

  alias Agentic.LLM.Transport.OpenAIChatCompletions, as: T

  defp build(messages) do
    T.build_chat_request(%{model: "m", messages: messages}, base_url: "http://x", api_key: "k")
    |> Map.fetch!(:body)
    |> Map.fetch!(:messages)
  end

  test "an assistant turn with tool_use blocks becomes tool_calls, never text markers" do
    [msg] =
      build([
        %{
          "role" => "assistant",
          "content" => [
            %{"type" => "text", "text" => "let me check"},
            %{
              "type" => "tool_use",
              "id" => "c1",
              "name" => "fs_read",
              "input" => %{"path" => "a.ex"}
            }
          ]
        }
      ])

    assert msg["content"] == "let me check"

    assert [%{"id" => "c1", "type" => "function", "function" => f}] = msg["tool_calls"]
    assert f["name"] == "fs_read"
    assert Jason.decode!(f["arguments"]) == %{"path" => "a.ex"}
    refute inspect(msg) =~ "[tool_use"
  end

  test "tool_result blocks become role:tool messages with tool_call_id" do
    msgs =
      build([
        %{
          "role" => "user",
          "content" => [
            %{"type" => "tool_result", "tool_use_id" => "c1", "content" => "file body"},
            %{"type" => "tool_result", "tool_use_id" => "c2", "content" => "other body"}
          ]
        }
      ])

    assert [
             %{"role" => "tool", "tool_call_id" => "c1", "content" => "file body"},
             %{"role" => "tool", "tool_call_id" => "c2", "content" => "other body"}
           ] = msgs
  end

  test "a mixed user turn keeps its text and maps its tool results" do
    msgs =
      build([
        %{
          "role" => "user",
          "content" => [
            %{"type" => "text", "text" => "here are the results"},
            %{"type" => "tool_result", "tool_use_id" => "c1", "content" => "data"}
          ]
        }
      ])

    assert [
             %{"role" => "user", "content" => "here are the results"},
             %{"role" => "tool", "tool_call_id" => "c1", "content" => "data"}
           ] = msgs
  end

  test "plain string messages pass through unchanged" do
    assert [%{"role" => "user", "content" => "hi"}] =
             build([%{"role" => "user", "content" => "hi"}])
  end

  test "a full tool round-trip produces the wire shape OpenAI providers expect" do
    msgs =
      build([
        %{"role" => "user", "content" => "read a.ex"},
        %{
          "role" => "assistant",
          "content" => [
            %{
              "type" => "tool_use",
              "id" => "c1",
              "name" => "fs_read",
              "input" => %{"path" => "a.ex"}
            }
          ]
        },
        %{
          "role" => "user",
          "content" => [%{"type" => "tool_result", "tool_use_id" => "c1", "content" => "body"}]
        }
      ])

    assert [
             %{"role" => "user"},
             %{"role" => "assistant", "tool_calls" => [_]},
             %{"role" => "tool", "tool_call_id" => "c1"}
           ] = msgs
  end
end
