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

import_config "#{config_env()}.exs"
