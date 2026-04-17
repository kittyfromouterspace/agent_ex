defmodule Agentic.Storage.Backend do
  @moduledoc """
  Behaviour for storage backend implementations.

  Formalizes the implicit 8-function contract that `Storage.Local` already
  implements. `Storage.Context` delegates to a backend module resolved by atom.
  """

  @callback read(config :: map(), path :: String.t()) ::
              {:ok, String.t()} | {:error, term()}

  @callback write(config :: map(), path :: String.t(), content :: String.t()) ::
              :ok | {:error, term()}

  @callback exists?(config :: map(), path :: String.t()) :: boolean()

  @callback dir?(config :: map(), path :: String.t()) :: boolean()

  @callback ls(config :: map(), path :: String.t()) ::
              {:ok, [String.t()]} | {:error, term()}

  @callback rm_rf(config :: map(), path :: String.t()) :: :ok

  @callback mkdir_p(config :: map(), path :: String.t()) ::
              :ok | {:error, term()}

  @callback materialize_local(config :: map(), path :: String.t()) ::
              {:ok, String.t()} | {:error, term()}
end
