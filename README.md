# Shazam Core

The backend engine of [Shazam](https://shazam.dev) — AI Agent Orchestration.

This package contains the core orchestration logic: task management, agent execution, context persistence, multi-provider support, plugins, and the REST API. It is used by:

- [shazam-cli](https://github.com/raphaelbarbosaqwerty/shazam-cli) — CLI + TUI interface
- [shazam-dashboard](https://github.com/ShazamAI/shazam-dashboard) — Web dashboard (Vue 3)
- shazam-vscode — VS Code extension (coming soon)

## What's inside

| Layer | Modules | Description |
|-------|---------|-------------|
| **Task System** | TaskBoard, TaskScheduler, TaskExecutor, SubtaskParser | Task CRUD, scheduling, execution, subtask parsing |
| **Execution Loop** | RalphLoop, SessionPool, Orchestrator | Polling, session reuse, parallel execution |
| **Organization** | Company, AgentWorker, Hierarchy, AgentPresets | Agent hierarchy, roles, presets |
| **Intelligence** | ContextManager, ContextRAG, GitContext, AgentQuery, AgentPulse | Context persistence, TF-IDF, git-awareness, agent queries |
| **Providers** | Provider, ClaudeCode, Codex, Cursor, Gemini | Multi-CLI abstraction |
| **Plugins** | Plugin, PluginManager, PluginLoader | 8 lifecycle hooks, runtime compilation |
| **API** | Router, EventBus, WebSocket | REST + WebSocket on configurable port |
| **Resilience** | CircuitBreaker, RetryPolicy, Metrics | Auto-pause, retry, token tracking |
| **Persistence** | Store, TaskFiles, FileLogger | JSON files, task markdown sync |

## Usage as dependency

```elixir
# mix.exs
defp deps do
  [
    {:shazam, github: "ShazamAI/shazam-core"}
  ]
end
```

## Running standalone

```bash
mix deps.get
iex -S mix
```

The API server starts on port 4040 (configurable).

## License

MIT
