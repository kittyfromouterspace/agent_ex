%Doctor.Config{
  min_overall_spec_coverage: 0,
  struct_type_spec_required: false,
  ignore_modules: [
    Agentic.AgentProtocol,
    Agentic.AgentProtocol.CLI,
    Agentic.ModelRouter.Free.Route,
    Agentic.Protocol.Error.NotFound,
    Agentic.Protocol.Error.Unavailable,
    Agentic.Protocol.Error.SessionError,
    Agentic.Storage.Context,
    Agentic.Subagent.Coordinator,
    Agentic.Tools,
    Agentic.Tools.Gateway,
    Agentic.Tools.Memory,
    Agentic.Tools.Skill
  ]
}
