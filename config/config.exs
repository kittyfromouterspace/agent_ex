import Config

config :agentic,
  telemetry_prefix: [:agentic],
  providers: [
    Agentic.LLM.Provider.Anthropic,
    Agentic.LLM.Provider.OpenAI,
    Agentic.LLM.Provider.OpenRouter,
    Agentic.LLM.Provider.Groq,
    Agentic.LLM.Provider.Ollama,
    Agentic.LLM.Provider.Zai,
    # Catalog-only Provider wrappers for CLI protocols (the actual
    # subprocess is owned by Agentic.Protocol.{ClaudeCode,OpenCode,Codex}).
    # Surfacing them here lets the multi-pathway router consider them as
    # alternatives within a canonical_id group.
    Agentic.LLM.Provider.ClaudeCode,
    Agentic.LLM.Provider.OpenCode,
    Agentic.LLM.Provider.Codex
  ],
  catalog: [
    persist_path: "~/.agentic/catalog.json",
    refresh_interval_ms: 600_000
  ]

config :ex_money,
  default_cldr_backend: Agentic.Cldr,
  # Don't auto-start the OXR retriever in agentic — Worth (or any other
  # host) configures the FX source. Without this, agentic would try to
  # spawn the OXR fetcher and emit warnings in environments without an
  # OXR app id.
  auto_start_exchange_rate_service: false

import_config "#{config_env()}.exs"
