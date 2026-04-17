import Config

config :agentic,
  telemetry_prefix: [:agentic],
  providers: [
    Agentic.LLM.Provider.Anthropic,
    Agentic.LLM.Provider.OpenAI,
    Agentic.LLM.Provider.OpenRouter,
    Agentic.LLM.Provider.Groq,
    Agentic.LLM.Provider.Ollama
  ],
  catalog: [
    persist_path: "~/.agentic/catalog.json",
    refresh_interval_ms: 600_000
  ]

import_config "#{config_env()}.exs"
