# Changelog

## v1.0.0 (2026-04-02) — Subagents & Intelligence Release

### Major Features
- **ConfigSync with Subagent Presets** — 12 specialized subagent templates (architect, executor, reviewer, explorer, debugger, test-writer, security-auditor, docs-writer, refactorer, planner, analyst, designer) synced to Claude Code, Gemini CLI, Cursor, and Codex
- **Namespaced Subagents** — per-agent subagent assignments (pm--planner, senior_1--executor) with `memory: project` and agent-memory directory pre-creation
- **ModelProxy** — maps model aliases (opus/sonnet/haiku) to provider-specific IDs across Claude, Gemini, Cursor, Codex
- **Auto-Model Routing** — tasks auto-routed to optimal model by complexity (simple→Haiku, complex→Sonnet, critical→Opus)
- **Smart Task Decomposition** — detects complex tasks and suggests PM decomposition before execution
- **Agent-to-Agent Collaboration** — agents can message each other with @agent_name in output
- **Memory Consolidation** — automatic 24h consolidation of agent context to reduce token usage
- **Webhook Notifications** — HTTP webhooks with HMAC-SHA256 signing for Slack/Discord
- **Audit Log** — records all important actions (task CRUD, project start/stop, config sync)
- **Context Window Monitor** — tracks input/output tokens per agent with warning at 80%
- **Agent Performance Scoring** — grade A-F per agent with actionable suggestions
- **Task Deduplication** — prevents duplicate tasks (same title + agent + active status)
- **Rate Limiting** — budget check before task execution, warning at 90%, block at 100%
- **Plans REST API** — create, edit, refine, approve plans without creating tasks until approval
- **ConfigImport** — import existing .claude/.gemini/.cursor configs into shazam.yaml
- **Shazam Doctor** — 11 system health checks via GET /api/doctor
- **YAML Writer** — direct shazam.yaml modification from dashboard (no copy-paste)
- **Multi-tenant Isolation** — sessions namespaced by company, per-company workspace

### Core Improvements
- **Source of Truth Hierarchy** — YAML > Store > GenServer clearly documented and enforced
- **Shazam.Config** — centralized workspace + budget resolution
- **Silent rescue blocks fixed** — ~70 catch blocks now log via Logger in 21 files
- **TaskBoard standardized** — all functions return {:ok, result} or {:error, reason}
- **Builder consolidated** — build_agent_configs delegates to build_agents_from_raw
- **unblock_dependents implemented** — queries + broadcasts task_unblocked events
- **RalphLoop refresh_agents** — Company notifies RalphLoop on agent updates
- **SessionPool rewritten** — no idle killing, compact instead of reset, grace period reaper
- **Task reimport on project start** — tasks loaded from workspace markdown files
- **Tool event parsing fixed** — parse_tool_content handles maps and strings
- **Prompt injection improved** — project memories, rules, decisions injected; subordinates for any agent with reports

### Bug Fixes
- Agent edit no longer wipes other agents (merge partial updates)
- Budget 0/nil = unlimited everywhere
- Tasks load correctly after daemon restart
- cli_exit 143 fixed (reaper grace period + child process tracking)
- parse_agents includes all fields (model, tools, skills, modules, system_prompt)

### Tests
- 680+ tests across all modules
- Coverage improved from 19% to 35%+

### Removed
- Nix support (flake.nix, setup.sh Nix detection)

## v0.5.3 (2026-03-25)

### Bug Fixes
- **Agent edit wipe protection** — `Company.update_agents` now rejects updates with fewer agents than current state, preventing dashboard edit from accidentally replacing the entire agent list.
- **Compilation warnings** — fixed all 6 warnings: unreachable HotReload clauses, unused variables, ungrouped EventBus clauses.

### Tests
- Added 269+ new tests across 12 modules (RetryPolicy, TaskTemplates, AgentPresets, SubtaskParser, Provider.Resolver, API.Helpers, PromptBuilder, Company.Builder, PlanManager, ProjectDetector, FileLogger, SkillMemory).
- Coverage improved from 19% to 24%, with 4 modules at 100%.

## v0.5.2 (2026-03-25)

### Features
- **Multi-stage workflow pipelines** — tasks can follow configurable workflows (e.g. Dev → Review → QA). Stages auto-assign to agents by role, advance on completion, and support rejection with rollback.
- **Workflow CRUD API** — `GET/POST/PUT/DELETE /api/workflows` for managing workflow templates stored as YAML in `.shazam/workflows/`.
- **Pipeline stage actions** — `POST /tasks/:id/approve-stage` and `/reject-stage` endpoints for manual stage approval/rejection.
- **EventBus event buffer** — stores last 50 events in a circular buffer, exposed via `GET /api/events/recent`.
- **Orphaned process cleanup** — SessionPool now detects and reaps orphaned OS-level Claude processes every 5 minutes.
- **Circuit breaker reset endpoint** — `POST /api/ralph-loop/reset-circuit-breaker` to reset tripped state from dashboard.
- **Enhanced config API** — `GET /api/config` now returns agents, domains, plugins, mission, tech stack, and health status.

### Improvements
- **Pipeline-aware task assignment** — `required_role` field routes tasks to matching agents by role.
- **Task serialization** — includes pipeline, workflow, current_stage, and required_role fields when present.
- **RalphLoop refactor** — extracted `handle_task_stage_completion` for pipeline-aware completion flow with stage advancement, events, and auto-QA.

### Bug Fixes
- **Ralph endpoint paths** — fixed `/api/ralph-loop/pause` and `/resume` route consistency.
- **Circuit breaker status** — included in health endpoint response.

## v0.5.1 (2026-03-25)

### Bug Fixes
- **Output capture fix** — `Stream.collect` replaces `Stream.final_result` for claude_code 0.33+ compatibility. `ResultMessage.result` is empty in v0.33; text is now captured from streaming collect.
- **PM prompt assertive** — PM no longer asks for confirmation. Added "NEVER ask questions, ALWAYS create subtasks immediately" to instructions.
- **Daemon PATH** — includes `~/.local/bin`, `~/.cargo/bin`, `~/.asdf/shims`, `~/.mise/shims`, `/opt/homebrew/bin` so `claude` CLI is found.
- **Config API** — added `GET /api/config` and `PUT /api/config/ralph-loop` endpoints for dashboard Configuration page.
- **claude_code pinned** — `~> 0.33` (was `~> 0.29`) to match installed version.

## v0.5.0 (2026-03-25)

### Features
- **Hot code reload** — `POST /api/daemon/reload` recompiles and reloads all modules without stopping processes. Zero downtime. GenServer state, WebSocket connections, and running tasks preserved.
- **FileWatcher** — polls workspace for file changes, broadcasts `file_created/changed/deleted` events via EventBus
- **File API** — `GET /api/files/tree`, `GET /api/files?path=`, `PUT /api/files` with path traversal protection
- **Sentry error tracking** — crash reporting for GenServer failures, API errors, daemon issues

### Bug Fixes
- **Agent zeroing bug (root cause)** — `build_agents_from_raw` only read string keys (`a["name"]`), now supports atom keys too (`a[:name]`). This was causing agents to lose their names when updated via WebSocket subscribe.
- **Company.update_agents guard** — rejects updates with empty or nameless agent lists, preventing accidental overwrites
- **Handle_start protection** — if company is already running, just resume RalphLoop without recreating agents

## v0.3.2 (2026-03-25)

### Features
- **ProjectRegistry** — persistent registry of known projects in `~/.shazam/projects.json`
  - Auto-registers projects when TUI subscribes via WebSocket
  - REST API: `GET/POST /api/projects`, `POST /:name/start|stop`, `DELETE /:name`
  - Start project from dashboard: reads shazam.yaml, boots company + agents
  - Tasks filterable by `?company=` query param

### Bug Fixes
- **YAML nested company.name** — supports both `name: "X"` and `company: { name: "X" }` formats
- **Name validation** — prevents saving maps as project names

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
