# Plugin: Structured JSON logs in .shazam/logs/
# Saves all task events as JSON lines for debugging and auditing.
# All text fields are automatically scrubbed for secrets before logging.
#
# Config (shazam.yaml):
#   plugins:
#     - name: json_logger
#       config:
#         log_dir: ".shazam/logs"   # optional, defaults to .shazam/logs
defmodule ShazamPlugin.JsonLogger do
  use Shazam.Plugin

  @default_dir ".shazam/logs"
  @log_file "events.json"

  # Patterns that match common secrets — same as secrets_obfuscation plugin
  @secret_patterns [
    ~r/sk-[a-zA-Z0-9]{20,}/,
    ~r/sk-ant-[a-zA-Z0-9\-]{20,}/,
    ~r/AIza[a-zA-Z0-9\-_]{35}/,
    ~r/ghp_[a-zA-Z0-9]{36}/,
    ~r/gho_[a-zA-Z0-9]{36}/,
    ~r/github_pat_[a-zA-Z0-9_]{82}/,
    ~r/glpat-[a-zA-Z0-9\-]{20}/,
    ~r/xoxb-[0-9]{10,}-[a-zA-Z0-9]{20,}/,
    ~r/xoxp-[0-9]{10,}-[a-zA-Z0-9]{20,}/,
    ~r/AKIA[A-Z0-9]{16}/,
    ~r/Bearer\s+[a-zA-Z0-9\-._~+\/]+=*/,
    ~r/eyJ[a-zA-Z0-9\-_]+\.eyJ[a-zA-Z0-9\-_]+/,
    ~r/-----BEGIN\s+(RSA\s+)?PRIVATE\s+KEY-----/,
    ~r/postgres:\/\/[^\s]+:[^\s]+@/,
    ~r/mysql:\/\/[^\s]+:[^\s]+@/,
    ~r/mongodb(\+srv)?:\/\/[^\s]+:[^\s]+@/,
    ~r/redis:\/\/:[^\s]+@/,
    ~r/password\s*[=:]\s*["'][^"']{8,}["']/i,
    ~r/secret\s*[=:]\s*["'][^"']{8,}["']/i,
    ~r/api_key\s*[=:]\s*["'][^"']{8,}["']/i,
    ~r/token\s*[=:]\s*["'][^"']{8,}["']/i,
  ]

  @impl true
  def on_init(ctx) do
    dir = log_dir(ctx)
    File.mkdir_p!(dir)

    log(ctx, "init", %{
      company: ctx.company_name,
      agents: length(ctx.agents)
    })
    :ok
  end

  @impl true
  def after_task_create(task, ctx) do
    log(ctx, "task_created", %{
      task_id: task.id,
      title: scrub(task.title),
      assigned_to: task.assigned_to,
      created_by: task.created_by
    })
    {:ok, task}
  end

  @impl true
  def after_task_complete(task_id, result, ctx) do
    preview = result |> to_string() |> String.slice(0..300)
    log(ctx, "task_completed", %{
      task_id: task_id,
      result_preview: scrub(preview)
    })
    {:ok, result}
  end

  @impl true
  def before_query(prompt, agent_name, ctx) do
    log(ctx, "query_sent", %{
      agent: agent_name,
      prompt_length: String.length(prompt)
      # Never log the prompt itself — could contain secrets
    })
    {:ok, prompt}
  end

  @impl true
  def on_tool_use(tool_name, input, agent_name, ctx) do
    log(ctx, "tool_use", %{
      agent: agent_name,
      tool: tool_name,
      input_preview: input |> inspect(limit: 100) |> String.slice(0..200) |> scrub()
    })
    :ok
  end

  # ── Secret scrubbing ──────────────────────────────

  defp scrub(nil), do: nil
  defp scrub(text) when is_binary(text) do
    Enum.reduce(@secret_patterns, text, fn pattern, acc ->
      Regex.replace(pattern, acc, "######")
    end)
    |> scrub_env_vars()
  end
  defp scrub(other), do: other

  defp scrub_env_vars(text) do
    env_vars = ~w(ANTHROPIC_API_KEY OPENAI_API_KEY GITHUB_TOKEN SLACK_WEBHOOK_URL
                  DATABASE_URL REDIS_URL AWS_SECRET_ACCESS_KEY AWS_ACCESS_KEY_ID
                  SUPABASE_KEY STRIPE_SECRET_KEY SENDGRID_API_KEY)

    Enum.reduce(env_vars, text, fn var, acc ->
      case System.get_env(var) do
        nil -> acc
        "" -> acc
        value when byte_size(value) > 6 -> String.replace(acc, value, "######")
        _ -> acc
      end
    end)
  end

  # ── Logging ───────────────────────────────────────

  defp log(ctx, event, data) do
    dir = log_dir(ctx)
    path = Path.join(dir, @log_file)

    entry = %{
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      event: event,
      company: ctx.company_name,
      data: data
    }

    File.write(path, Jason.encode!(entry) <> "\n", [:append])
  rescue
    _ -> :ok
  end

  defp log_dir(ctx) do
    base = ctx.plugin_config["log_dir"] || @default_dir
    workspace = Application.get_env(:shazam, :workspace, File.cwd!())
    Path.join(workspace, base)
  end
end
