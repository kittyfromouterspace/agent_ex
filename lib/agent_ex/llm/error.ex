defmodule AgentEx.LLM.Error do
  @moduledoc """
  Normalized error returned from a transport's `parse_chat_response/3`
  (or surfaced from a transport network failure).

  ## Classification taxonomy

  `:classification` is one of:

    * `:rate_limit`       — HTTP 429, throttled, quota exceeded
    * `:overloaded`       — 503 + capacity language
    * `:auth`             — 401, ambiguous auth issue
    * `:auth_permanent`   — key revoked/disabled/deleted
    * `:billing`          — 402, insufficient credits
    * `:timeout`          — network timeout, connection reset
    * `:format`           — bad request format (bug in our request)
    * `:model_not_found`  — 404, model deactivated
    * `:context_overflow` — input too long (doesn't trigger failover)
    * `:session_expired`  — 410, needs reauth
    * `:transient`        — generic 5xx, unknown server-side issue
    * `:permanent`        — everything else
  """

  @type classification ::
          :rate_limit
          | :overloaded
          | :auth
          | :auth_permanent
          | :billing
          | :timeout
          | :format
          | :model_not_found
          | :context_overflow
          | :session_expired
          | :transient
          | :permanent

  @type t :: %__MODULE__{
          message: String.t(),
          status: non_neg_integer() | nil,
          retry_after_ms: non_neg_integer() | nil,
          rate_limit: AgentEx.LLM.RateLimit.t() | nil,
          classification: classification(),
          raw: term()
        }

  defstruct message: "",
            status: nil,
            retry_after_ms: nil,
            rate_limit: nil,
            classification: :permanent,
            raw: nil
end
