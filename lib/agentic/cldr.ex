defmodule Agentic.Cldr do
  @moduledoc """
  CLDR backend for `:ex_money`. Defines the locales and currencies that
  `Money` knows how to format and convert. We carry just enough to handle
  the currencies LLM providers bill in (USD, CNY, EUR, GBP, JPY) and the
  default `:en` locale; hosts that need more can re-configure
  `:default_cldr_backend` to their own backend.
  """

  use Cldr,
    locales: ["en"],
    default_locale: "en",
    providers: [Cldr.Number, Money]
end
