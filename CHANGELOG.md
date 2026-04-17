# Changelog

## 0.1.9 (2026-04-17)

Initial release.

- Composable middleware-style agent pipeline with stage modules
- Four built-in profiles: `:agentic`, `:agentic_planned`, `:turn_by_turn`, `:conversational`
- Built-in tools: file read/write/edit, glob, grep, bash, memory, skills, gateway
- YAML-based skill system with core skills (agent-tools, human-agency, tool-discovery)
- Working memory with context keeper, fact extraction, and commitment detection
- Persistence behaviours for transcript, plan, and knowledge with pluggable backends
- Local file-based backends for all persistence layers
- Recollect-backed knowledge backend for hybrid vector + graph search
- Model routing with automatic fallback and per-model health tracking
- Per-session cost limits and token usage tracking
- Full telemetry instrumentation
- ACP (Agent Communication Protocol) support with discovery and session management
- Additional protocols: Claude Code, OpenCode, Codex
- Sub-agent coordination via spawn_subagent
- Strategy system for orchestration (default + experiment)
- Circuit breaker for tool execution
- Bubblewrap sandbox support (Linux)
