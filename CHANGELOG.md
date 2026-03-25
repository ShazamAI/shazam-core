# Changelog

## v0.3.0 (2026-03-24)

### Features
- **Daemon mode** — run shazam-core as a persistent background service with `SHAZAM_DAEMON=true`
  - `Shazam.Daemon` GenServer manages PID file (`~/.shazam/daemon.pid`) and health
  - Auto-starts when `SHAZAM_DAEMON=true` env var is set
  - Multiple projects/companies run simultaneously in the same daemon
- **Full WebSocket command handler** — `Shazam.API.WebSocketCommands` handles all TUI commands server-side
  - `/start`, `/stop`, `/resume`, `/restart`, `/dashboard`, `/tasks`, `/agents`
  - `/task`, `/approve`, `/reject`, `/kill-task`, `/delete-task`, `/pause-task`, `/resume-task`
  - `/plan`, `/qa`, `/memory`, `/workspaces`, `/health`, `/search`, `/export`
  - Text without `/` prefix creates a task (same as inline mode)
- **Enhanced WebSocket protocol** — `Shazam.API.WebSocket` rewritten for full TUI support
  - `subscribe` action for project registration (company, workspace, agents, config)
  - `command` action for executing TUI commands
  - Rich event forwarding: agent_output, tool_use, approvals, status updates
  - Company-scoped event filtering for multi-project isolation
- **Health API enriched** — `GET /api/health` now returns companies, memory, PID, port

## v0.2.5 (2026-03-24)

### Bug Fixes
- **FileLogger compile-time path** — `@log_dir Path.expand("~/.shazam/logs")` baked builder's home dir into escript binary. Other users got "permission denied" trying to create `/Users/raphaelbarbosa/.shazam/logs`. Converted to runtime `log_dir()` function.

## v0.2.3 (2026-03-24)

### Bug Fixes
- Auto-assign unassigned tasks to top of hierarchy (Manager/PM)
- Store data_dir resolved at runtime (fixes permission denied on other machines)
- FIFO task ordering (oldest tasks execute first)
- Cursor provider uses `cursor-agent` binary with correct args
- Gemini provider uses `-p` flag for prompts

### Improvements
- Rich plan output (summary, architecture, acceptance criteria, risks)
- Plugin name matching normalized

## v0.2.0 (2026-03-24)

### Features
- **excluded_paths in domain config** — agents can be blocked from specific subdirectories even within allowed paths
- **Dashboard advanced metrics** — `Metrics.get_dashboard_stats/0` returns avg task duration, tasks/hour, tokens/task, retry rate, total cost
- **QA generates real test code** — `QAManager.generate_test_task/1` creates tasks for QA agents to write and run actual tests, not just checklists
- **Plugin name matching** — `normalize/1` handles underscore/camelCase differences (github_projects matches GitHubProjects)

### Example Plugins
- `05_github_projects.ex` — sync tasks with GitHub org-level Projects
- `06_json_logger.ex` — structured JSON event logs in `.shazam/logs/events.json`
- `07_secrets_obfuscation.ex` — detects 20+ secret patterns (API keys, JWTs, passwords, DB URLs, env vars) and replaces with ######

## v0.1.0 (2026-03-23)

### Initial Release
- Backend engine extracted from shazam-cli
- 55 Elixir modules, 49 tests
- TaskBoard, RalphLoop, SessionPool, Orchestrator
- Company, AgentWorker (implements Access), Hierarchy, 11 presets
- ContextManager, ContextRAG (TF-IDF), GitContext, AgentQuery, AgentPulse
- Providers: ClaudeCode, Codex, Cursor, Gemini
- Plugins: 8 lifecycle hooks, event filtering, runtime compilation
- API: REST + WebSocket on port 4040
- CircuitBreaker, RetryPolicy, Metrics, Store (JSON)
