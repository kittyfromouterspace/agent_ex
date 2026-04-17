defmodule Agentic.LLM.RateLimit do
  @moduledoc """
  Snapshot of rate-limit headers returned by a provider on the most
  recent response. Transports populate whichever fields they can parse;
  missing fields stay `nil`.
  """

  @type t :: %__MODULE__{
          remaining: non_neg_integer() | nil,
          limit: non_neg_integer() | nil,
          reset_at_ms: non_neg_integer() | nil
        }

  defstruct remaining: nil, limit: nil, reset_at_ms: nil
end
