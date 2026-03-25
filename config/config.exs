import Config

config :shazam,
  codex_fallback_enabled: true,
  codex_fallback_model: System.get_env("CODEX_FALLBACK_MODEL") || "gpt-5-codex",
  codex_cli_bin: System.get_env("CODEX_CLI_BIN") || "codex",
  codex_fallback_timeout_ms: 1_800_000,
  codex_progress_interval_ms: 15_000

config :claude_code, cli_path: :global

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Sentry error tracking
config :sentry,
  dsn: "https://1b3fbab3f097b65e9fb8b8c978383c2e@o4505191293779968.ingest.us.sentry.io/4511106667970560",
  environment_name: config_env(),
  enable_source_code_context: true,
  root_source_code_paths: [File.cwd!()],
  tags: %{app: "shazam-core"},
  included_environments: [:prod]

import_config "#{config_env()}.exs"
