import Config

config :agent_ex,
  telemetry_prefix: [:agent_ex],
  providers: [
    AgentEx.LLM.Provider.Anthropic,
    AgentEx.LLM.Provider.OpenAI,
    AgentEx.LLM.Provider.OpenRouter,
    AgentEx.LLM.Provider.Groq
  ]

import_config "#{config_env()}.exs"
