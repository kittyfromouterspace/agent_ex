defmodule AgentEx.LLM.ErrorClassifierTest do
  use ExUnit.Case, async: true

  alias AgentEx.LLM.ErrorClassifier

  describe "classify/4 — status code baseline" do
    test "402 → :billing" do
      assert {classification, _} = ErrorClassifier.classify(402, "error", [])
      assert classification == :billing
    end

    test "401 → :auth" do
      assert {classification, _} = ErrorClassifier.classify(401, "error", [])
      assert classification == :auth
    end

    test "403 → :auth_permanent" do
      assert {classification, _} = ErrorClassifier.classify(403, "error", [])
      assert classification == :auth_permanent
    end

    test "404 → :model_not_found" do
      assert {classification, _} = ErrorClassifier.classify(404, "error", [])
      assert classification == :model_not_found
    end

    test "408 → :timeout" do
      assert {classification, _} = ErrorClassifier.classify(408, "error", [])
      assert classification == :timeout
    end

    test "429 → :rate_limit" do
      assert {classification, _} = ErrorClassifier.classify(429, "error", [])
      assert classification == :rate_limit
    end

    test "500 → :transient" do
      assert {classification, _} = ErrorClassifier.classify(500, "error", [])
      assert classification == :transient
    end

    test "502 → :transient" do
      assert {classification, _} = ErrorClassifier.classify(502, "error", [])
      assert classification == :transient
    end

    test "504 → :transient" do
      assert {classification, _} = ErrorClassifier.classify(504, "error", [])
      assert classification == :transient
    end

    test "410 → :session_expired" do
      assert {classification, _} = ErrorClassifier.classify(410, "error", [])
      assert classification == :session_expired
    end
  end

  describe "classify/4 — pattern fallback" do
    test "pattern fallback when status is nil" do
      assert {classification, _} = ErrorClassifier.classify(nil, "rate limit exceeded", [])
      assert classification == :rate_limit
    end

    test "pattern fallback from body with error.message" do
      body = %{"error" => %{"message" => "insufficient credits"}}
      assert {classification, _} = ErrorClassifier.classify(nil, body, [])
      assert classification == :billing
    end
  end

  describe "classify/4 — context_overflow override" do
    test "context_overflow detected even on non-400 status" do
      msg = "input token count exceeds the maximum number of input tokens"
      assert {classification, _} = ErrorClassifier.classify(400, msg, [])
      assert classification == :context_overflow
    end

    test "context_overflow detected via heuristic" do
      msg = "tokens exceeds the model maximum limit"
      assert {classification, _} = ErrorClassifier.classify(200, msg, [])
      assert classification == :context_overflow
    end
  end

  describe "classify/4 — provider-specific override" do
    defmodule FakeProvider do
      def classify_http_error(1311, _body, _headers), do: {:billing, nil}
      def classify_http_error(_, _, _), do: :default
    end

    test "provider override takes priority" do
      assert {classification, _} = ErrorClassifier.classify(1311, "error", [], FakeProvider)
      assert classification == :billing
    end

    test "falls through when provider returns :default" do
      assert {classification, _} = ErrorClassifier.classify(429, "error", [], FakeProvider)
      assert classification == :rate_limit
    end
  end

  describe "classify/4 — permanent fallback" do
    test "unknown status code falls to permanent" do
      assert {classification, _} = ErrorClassifier.classify(418, "I'm a teapot", [])
      assert classification == :permanent
    end
  end
end
