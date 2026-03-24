# Plugin: Secrets Obfuscation
# Detects secrets in prompts before sending to AI and replaces with ######.
# Prevents API keys, tokens, passwords from leaking to AI providers.
#
# Config (shazam.yaml):
#   plugins:
#     - name: secrets_obfuscation
#       events: [before_query, before_task_create]
#       config:
#         # Additional patterns to detect (regex strings)
#         extra_patterns:
#           - "CUSTOM_SECRET_[A-Z0-9]+"
#         # Custom env var names to detect
#         env_vars:
#           - "MY_INTERNAL_TOKEN"
defmodule ShazamPlugin.SecretsObfuscation do
  use Shazam.Plugin

  @builtin_patterns [
    # API Keys
    ~r/sk-[a-zA-Z0-9]{20,}/,                          # OpenAI
    ~r/sk-ant-[a-zA-Z0-9\-]{20,}/,                    # Anthropic
    ~r/AIza[a-zA-Z0-9\-_]{35}/,                        # Google
    ~r/ghp_[a-zA-Z0-9]{36}/,                           # GitHub PAT
    ~r/gho_[a-zA-Z0-9]{36}/,                           # GitHub OAuth
    ~r/github_pat_[a-zA-Z0-9_]{82}/,                   # GitHub fine-grained
    ~r/glpat-[a-zA-Z0-9\-]{20}/,                       # GitLab
    ~r/xoxb-[0-9]{10,}-[a-zA-Z0-9]{20,}/,             # Slack Bot
    ~r/xoxp-[0-9]{10,}-[a-zA-Z0-9]{20,}/,             # Slack User

    # AWS
    ~r/AKIA[A-Z0-9]{16}/,                              # AWS Access Key
    ~r/[a-zA-Z0-9\/+=]{40}/,                           # AWS Secret (when near AKIA)

    # Tokens / Secrets
    ~r/Bearer\s+[a-zA-Z0-9\-._~+\/]+=*/,              # Bearer tokens
    ~r/eyJ[a-zA-Z0-9\-_]+\.eyJ[a-zA-Z0-9\-_]+/,      # JWT
    ~r/-----BEGIN\s+(RSA\s+)?PRIVATE\s+KEY-----/,      # Private keys

    # Database URLs
    ~r/postgres:\/\/[^\s]+:[^\s]+@/,                   # PostgreSQL connection
    ~r/mysql:\/\/[^\s]+:[^\s]+@/,                      # MySQL connection
    ~r/mongodb(\+srv)?:\/\/[^\s]+:[^\s]+@/,            # MongoDB connection
    ~r/redis:\/\/:[^\s]+@/,                            # Redis connection

    # Generic patterns
    ~r/password\s*[=:]\s*["'][^"']{8,}["']/i,          # password = "..."
    ~r/secret\s*[=:]\s*["'][^"']{8,}["']/i,            # secret = "..."
    ~r/api_key\s*[=:]\s*["'][^"']{8,}["']/i,           # api_key = "..."
    ~r/token\s*[=:]\s*["'][^"']{8,}["']/i,             # token = "..."
  ]

  @impl true
  def before_query(prompt, agent_name, ctx) do
    {cleaned, count} = obfuscate(prompt, ctx)

    if count > 0 do
      log_detection(ctx, agent_name, count, "query")
    end

    {:ok, cleaned}
  end

  @impl true
  def before_task_create(attrs, ctx) do
    title = attrs[:title] || ""
    desc = attrs[:description] || ""

    {clean_title, c1} = obfuscate(title, ctx)
    {clean_desc, c2} = obfuscate(desc, ctx)

    total = c1 + c2
    if total > 0 do
      log_detection(ctx, "task_create", total, "task")
    end

    {:ok, %{attrs | title: clean_title, description: clean_desc}}
  end

  # ── Core obfuscation ─────────────────────────────

  defp obfuscate(text, ctx) when is_binary(text) do
    patterns = all_patterns(ctx)

    # Also detect env var values
    env_patterns = build_env_patterns(ctx)
    all = patterns ++ env_patterns

    {cleaned, count} = Enum.reduce(all, {text, 0}, fn pattern, {txt, cnt} ->
      case Regex.scan(pattern, txt) do
        [] -> {txt, cnt}
        matches ->
          replaced = Regex.replace(pattern, txt, "######")
          {replaced, cnt + length(matches)}
      end
    end)

    {cleaned, count}
  end
  defp obfuscate(text, _ctx), do: {text, 0}

  defp all_patterns(ctx) do
    extra = ctx.plugin_config["extra_patterns"] || []
    custom = Enum.flat_map(extra, fn pattern_str ->
      case Regex.compile(pattern_str) do
        {:ok, regex} -> [regex]
        _ -> []
      end
    end)
    @builtin_patterns ++ custom
  end

  defp build_env_patterns(ctx) do
    env_vars = (ctx.plugin_config["env_vars"] || []) ++
      ~w(ANTHROPIC_API_KEY OPENAI_API_KEY GITHUB_TOKEN SLACK_WEBHOOK_URL
         DATABASE_URL REDIS_URL AWS_SECRET_ACCESS_KEY AWS_ACCESS_KEY_ID
         SUPABASE_KEY SUPABASE_URL STRIPE_SECRET_KEY SENDGRID_API_KEY)

    Enum.flat_map(env_vars, fn var ->
      case System.get_env(var) do
        nil -> []
        "" -> []
        value when byte_size(value) > 6 ->
          escaped = Regex.escape(value)
          case Regex.compile(escaped) do
            {:ok, regex} -> [regex]
            _ -> []
          end
        _ -> []
      end
    end)
  end

  defp log_detection(ctx, source, count, context) do
    try do
      workspace = Application.get_env(:shazam, :workspace, File.cwd!())
      log_path = Path.join([workspace, ".shazam", "logs", "secrets.log"])
      File.mkdir_p!(Path.dirname(log_path))

      entry = "[#{DateTime.utc_now() |> DateTime.to_iso8601()}] " <>
        "OBFUSCATED #{count} secret(s) in #{context} from #{source} " <>
        "(company: #{ctx.company_name})\n"

      File.write(log_path, entry, [:append])
    rescue
      _ -> :ok
    end
  end
end
