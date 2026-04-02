defmodule Shazam.API.Routes.MiscRoutes do
  @moduledoc "Handles sessions, metrics, agent inbox, health, presets, and templates. Forwarded with prefix /api stripped."

  use Plug.Router
  require Logger

  import Shazam.API.Helpers

  plug :match
  plug :dispatch

  # --- Sessions ---

  get "/sessions" do
    sessions = Shazam.SessionPool.list()
    json(conn, 200, %{sessions: sessions})
  end

  post "/sessions/kill-all" do
    {:ok, count} = Shazam.SessionPool.kill_all()
    json(conn, 200, %{status: "ok", killed: count})
  end

  delete "/sessions/:agent_name" do
    Shazam.SessionPool.kill(agent_name)
    json(conn, 200, %{status: "killed", agent: agent_name})
  end

  # --- Metrics ---

  get "/metrics" do
    metrics = Shazam.Metrics.get_all()
    json(conn, 200, metrics)
  end

  get "/metrics/:agent_name" do
    case Shazam.Metrics.get_agent(agent_name) do
      nil -> json(conn, 404, %{error: "No metrics for agent '#{agent_name}'"})
      metrics -> json(conn, 200, %{agent: agent_name, metrics: metrics})
    end
  end

  # --- Task Templates ---

  get "/task-templates" do
    json(conn, 200, %{templates: Shazam.TaskTemplates.list()})
  end

  # --- Agent Presets ---

  get "/agent-presets" do
    presets = Shazam.AgentPresets.list()
    json(conn, 200, %{presets: presets})
  end

  # --- Subagent Presets ---

  get "/subagent-presets" do
    presets = Shazam.SubagentPresets.all()
      |> Enum.map(fn {name, p} ->
        %{
          name: name,
          description: p.description,
          default_model: p.default_model,
          readonly: p.readonly,
          level: p.level,
          tools: p.tools
        }
      end)
      |> Enum.sort_by(& &1.name)

    json(conn, 200, %{presets: presets})
  end

  # --- Workflows ---

  get "/workflows" do
    workspace = Application.get_env(:shazam, :workspace, nil)
    workflows = Shazam.Workflow.list_all(workspace)
      |> Enum.map(fn w ->
        %{
          name: w.name,
          stages: Enum.map(w.stages, fn s ->
            %{name: s.name, role: s.role, prompt_suffix: s.prompt_suffix, on_reject: s.on_reject}
          end)
        }
      end)
    json(conn, 200, %{workflows: workflows})
  end

  post "/workflows" do
    workspace = Application.get_env(:shazam, :workspace, nil)
    name = conn.body_params["name"]
    stages_raw = conn.body_params["stages"] || []

    cond do
      !workspace ->
        json(conn, 400, %{error: "No workspace set"})
      !name || name == "" ->
        json(conn, 400, %{error: "name is required"})
      length(stages_raw) == 0 ->
        json(conn, 400, %{error: "At least one stage is required"})
      true ->
        dir = Path.join(workspace, ".shazam/workflows")
        File.mkdir_p!(dir)
        path = Path.join(dir, "#{name}.yml")

        yaml_content = """
        name: #{name}
        stages:
        #{Enum.map_join(stages_raw, "\n", fn s ->
          on_reject = if s["on_reject"], do: "\n    on_reject: #{s["on_reject"]}", else: ""
          prompt = if s["prompt_suffix"], do: "\n    prompt_suffix: \"#{String.replace(s["prompt_suffix"] || "", "\"", "\\\"")}\"", else: ""
          "  - name: #{s["name"]}\n    role: #{s["role"]}#{prompt}#{on_reject}"
        end)}
        """

        case File.write(path, yaml_content) do
          :ok -> json(conn, 201, %{status: "ok", name: name, path: path})
          {:error, reason} -> json(conn, 500, %{error: "Write failed: #{reason}"})
        end
    end
  end

  put "/workflows/:name" do
    workspace = Application.get_env(:shazam, :workspace, nil)
    stages_raw = conn.body_params["stages"] || []

    cond do
      !workspace ->
        json(conn, 400, %{error: "No workspace set"})
      length(stages_raw) == 0 ->
        json(conn, 400, %{error: "At least one stage is required"})
      true ->
        dir = Path.join(workspace, ".shazam/workflows")
        File.mkdir_p!(dir)
        path = Path.join(dir, "#{name}.yml")

        yaml_content = """
        name: #{name}
        stages:
        #{Enum.map_join(stages_raw, "\n", fn s ->
          on_reject = if s["on_reject"], do: "\n    on_reject: #{s["on_reject"]}", else: ""
          prompt = if s["prompt_suffix"], do: "\n    prompt_suffix: \"#{String.replace(s["prompt_suffix"] || "", "\"", "\\\"")}\"", else: ""
          "  - name: #{s["name"]}\n    role: #{s["role"]}#{prompt}#{on_reject}"
        end)}
        """

        case File.write(path, yaml_content) do
          :ok -> json(conn, 200, %{status: "ok", name: name})
          {:error, reason} -> json(conn, 500, %{error: "Write failed: #{reason}"})
        end
    end
  end

  delete "/workflows/:name" do
    workspace = Application.get_env(:shazam, :workspace, nil)
    if workspace do
      path = Path.join(workspace, ".shazam/workflows/#{name}.yml")
      File.rm(path)
      json(conn, 200, %{status: "ok"})
    else
      json(conn, 400, %{error: "No workspace set"})
    end
  end

  get "/workflows/:name" do
    workspace = Application.get_env(:shazam, :workspace, nil)
    case Shazam.Workflow.get(name, workspace) do
      nil -> json(conn, 404, %{error: "Workflow '#{name}' not found"})
      w ->
        json(conn, 200, %{workflow: %{
          name: w.name,
          stages: Enum.map(w.stages, fn s ->
            %{name: s.name, role: s.role, prompt_suffix: s.prompt_suffix, on_reject: s.on_reject}
          end)
        }})
    end
  end

  # --- Config ---

  get "/config" do
    company_name = try do
      Registry.select(Shazam.CompanyRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
      |> List.first()
      |> to_string()
    catch
      kind, reason ->
        Logger.debug("[MiscRoutes] Failed to get company name: #{inspect(kind)}: #{inspect(reason)}")
        nil
    end

    ralph_config = if company_name do
      try do
        status = Shazam.RalphLoop.status(company_name)
        %{
          auto_approve: status[:auto_approve] || false,
          max_concurrent: status[:max_concurrent] || 4,
          poll_interval: status[:poll_interval] || 5000,
          module_lock: status[:module_lock] || true,
          peer_reassign: status[:peer_reassign] || true,
          auto_retry: status[:auto_retry] || true,
          max_retries: status[:max_retries] || 2
        }
      catch
        kind, reason ->
          Logger.debug("[MiscRoutes] Failed to get RalphLoop config: #{inspect(kind)}: #{inspect(reason)}")
          %{}
      end
    else
      %{}
    end

    workspace = Application.get_env(:shazam, :workspace, nil)

    # Build agents map from company
    agents = if company_name do
      try do
        Shazam.Company.get_agents(company_name)
        |> Enum.reduce(%{}, fn agent, acc ->
          Map.put(acc, agent.name, %{
            role: agent.role,
            supervisor: agent.supervisor,
            budget: agent.budget || 0,
            model: agent.model,
            fallback_model: Map.get(agent, :fallback_model),
            provider: Map.get(agent, :provider),
            tools: agent.tools || [],
            skills: Map.get(agent, :skills) || [],
            modules: Map.get(agent, :modules) || [],
            domain: agent.domain,
            workspace: Map.get(agent, :workspace),
            system_prompt: Map.get(agent, :system_prompt),
            heartbeat_interval: Map.get(agent, :heartbeat_interval, 60000)
          })
        end)
      catch
        kind, reason ->
          Logger.debug("[MiscRoutes] Failed to get agents: #{inspect(kind)}: #{inspect(reason)}")
          %{}
      end
    else
      %{}
    end

    # Build domains from company domain_config
    domains = if company_name do
      try do
        Shazam.Company.get_domain_config(company_name) || %{}
      catch
        kind, reason ->
          Logger.debug("[MiscRoutes] Failed to get domain config: #{inspect(kind)}: #{inspect(reason)}")
          %{}
      end
    else
      %{}
    end

    # Get tech stack from app config
    tech_stack = Application.get_env(:shazam, :tech_stack, %{}) || %{}

    # Get plugins
    plugins = try do
      Shazam.PluginManager.list_plugins()
      |> Enum.map(fn p ->
        %{
          name: p[:name] || "unknown",
          enabled: p[:enabled] != false,
          events: p[:events] || [],
          config: p[:config] || %{}
        }
      end)
    catch
      kind, reason ->
        Logger.debug("[MiscRoutes] Failed to list plugins: #{inspect(kind)}: #{inspect(reason)}")
        []
    end

    # Get mission from company info
    {mission, company_info_workspace} = if company_name do
      try do
        info = Shazam.Company.info(company_name)
        {info[:mission], info[:workspace]}
      catch
        kind, reason ->
          Logger.debug("[MiscRoutes] Failed to get company info: #{inspect(kind)}: #{inspect(reason)}")
          {nil, nil}
      end
    else
      {nil, nil}
    end

    json(conn, 200, %{
      provider: to_string(Application.get_env(:shazam, :default_provider, "claude_code")),
      company: %{
        name: company_name,
        mission: mission,
        workspace: workspace || company_info_workspace
      },
      domains: domains,
      workspaces: %{},
      tech_stack: tech_stack,
      agents: agents,
      config: ralph_config,
      plugins: plugins,
      qa_auto: Application.get_env(:shazam, :qa_auto, false),
      qa_routing: Application.get_env(:shazam, :qa_routing, false)
    })
  end

  put "/config/ralph-loop" do
    company = try do
      Registry.select(Shazam.CompanyRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
      |> List.first()
      |> to_string()
    catch
      kind, reason ->
        Logger.debug("[MiscRoutes] Failed to get company for config update: #{inspect(kind)}: #{inspect(reason)}")
        nil
    end

    if company && Shazam.RalphLoop.exists?(company) do
      params = conn.body_params
      if params["auto_approve"] != nil, do: Shazam.RalphLoop.set_auto_approve(company, params["auto_approve"])
      if params["max_concurrent"], do: Shazam.RalphLoop.set_config(company, "max_concurrent", params["max_concurrent"])
      if params["poll_interval"], do: Shazam.RalphLoop.set_config(company, "poll_interval", params["poll_interval"])
      if params["module_lock"] != nil, do: Shazam.RalphLoop.set_config(company, "module_lock", params["module_lock"])
      if params["peer_reassign"] != nil, do: Shazam.RalphLoop.set_config(company, "peer_reassign", params["peer_reassign"])
      if params["auto_retry"] != nil, do: Shazam.RalphLoop.set_config(company, "auto_retry", params["auto_retry"])
      json(conn, 200, %{ok: true})
    else
      json(conn, 404, %{error: "No active company"})
    end
  end

  # --- Webhooks ---

  get "/webhooks" do
    webhooks = Shazam.Webhook.list()

    json(conn, 200, %{
      webhooks:
        Enum.map(webhooks, fn w ->
          %{url: w.url, events: w.events, active: w.active}
        end)
    })
  end

  post "/webhooks" do
    url = conn.body_params["url"]
    events = conn.body_params["events"]
    secret = conn.body_params["secret"]

    if !url || url == "" do
      json(conn, 400, %{error: "url is required"})
    else
      opts = []
      opts = if events, do: [{:events, events} | opts], else: opts
      opts = if secret, do: [{:secret, secret} | opts], else: opts

      Shazam.Webhook.register(url, opts)
      json(conn, 201, %{status: "ok"})
    end
  end

  delete "/webhooks" do
    url = conn.body_params["url"]
    Shazam.Webhook.unregister(url)
    json(conn, 200, %{status: "ok"})
  end

  # --- Events ---

  get "/events/recent" do
    # Return recent events from the EventBus buffer (last 50)
    events = try do
      Shazam.API.EventBus.recent_events()
    catch
      kind, reason ->
        Logger.debug("[MiscRoutes] Failed to get recent events: #{inspect(kind)}: #{inspect(reason)}")
        []
    end
    json(conn, 200, %{events: events})
  end

  # --- Context/Memory Tree ---

  get "/context/tree" do
    workspace = Application.get_env(:shazam, :workspace, nil)
    context_dir = if workspace, do: Path.join(workspace, ".shazam/context"), else: nil

    tree = if context_dir && File.dir?(context_dir) do
      build_context_tree(context_dir, context_dir)
    else
      # Fallback: use memory-banks data
      banks = Shazam.SkillMemory.list_all()
      Enum.map(banks, fn s ->
        %{name: Path.basename(s.path), path: s.path, type: "file", children: []}
      end)
    end

    json(conn, 200, %{tree: tree})
  end

  get "/context/file" do
    workspace = Application.get_env(:shazam, :workspace, nil)
    rel_path = conn.query_params["path"] || ""
    context_dir = if workspace, do: Path.join(workspace, ".shazam/context"), else: nil

    cond do
      context_dir == nil ->
        json(conn, 400, %{error: "No workspace set"})
      true ->
        full_path = Path.join(context_dir, rel_path)
        if File.regular?(full_path) do
          content = File.read!(full_path)
          json(conn, 200, %{file: %{path: rel_path, content: content, name: Path.basename(rel_path)}})
        else
          json(conn, 404, %{error: "File not found"})
        end
    end
  end

  # --- Audit Log ---

  get "/audit-log" do
    limit = (conn.params["limit"] || "50") |> String.to_integer() |> min(200)
    action = conn.params["action"]

    entries = if action do
      Shazam.AuditLog.filter(action, limit)
    else
      Shazam.AuditLog.recent(limit)
    end

    json(conn, 200, %{entries: entries})
  end

  # --- Hot Reload ---

  post "/daemon/reload" do
    {:ok, result} = Shazam.HotReload.reload()
    case result.compile do
      :ok -> json(conn, 200, result)
      {:error, reason} -> json(conn, 500, %{error: inspect(reason)})
    end
  end

  # --- Doctor (diagnostics) ---

  get "/doctor" do
    result = Shazam.Doctor.diagnose()
    status_code = if result.failed > 0, do: 503, else: 200
    json(conn, status_code, result)
  end

  # --- Health ---

  get "/health" do
    workspace = Application.get_env(:shazam, :workspace, nil)
    memory_mb = div(:erlang.memory(:total), 1_048_576)

    companies = try do
      Registry.select(Shazam.CompanyRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
      |> Enum.map(&to_string/1)
    rescue
      e ->
        Logger.debug("[MiscRoutes] Failed to list companies: #{Exception.message(e)}")
        []
    catch
      kind, reason ->
        Logger.debug("[MiscRoutes] Failed to list companies: #{inspect(kind)}: #{inspect(reason)}")
        []
    end

    pid = to_string(:os.getpid())
    port = Application.get_env(:shazam, :port, 4040)

    circuit_breaker_tripped = try do
      Shazam.CircuitBreaker.tripped?()
    catch
      kind, reason ->
        Logger.debug("[MiscRoutes] Failed to check circuit breaker: #{inspect(kind)}: #{inspect(reason)}")
        false
    end

    json(conn, 200, %{
      status: "ok",
      version: "0.2.5",
      workspace: workspace,
      memory_mb: memory_mb,
      companies: companies,
      pid: pid,
      port: port,
      circuit_breaker_tripped: circuit_breaker_tripped
    })
  end

  # --- Memory Consolidation ---

  post "/memory/consolidate" do
    case Shazam.MemoryConsolidator.consolidate_all() do
      {:ok, results} -> json(conn, 200, %{status: "ok", results: results})
      {:error, reason} -> json(conn, 500, %{error: inspect(reason)})
    end
  end

  get "/memory/consolidation-status" do
    status = Shazam.MemoryConsolidator.status()

    json(conn, 200, %{
      last_run: if(status.last_run, do: DateTime.to_iso8601(status.last_run), else: nil),
      results: status.results
    })
  end

  # --- Legacy Memory Banks ---

  get "/memory-banks" do
    banks = Shazam.SkillMemory.list_all()
      |> Enum.filter(fn s -> String.starts_with?(s.path, "agents/") end)
      |> Enum.map(fn s -> %{agent: s.name, content: s.content, path: s.path} end)
    json(conn, 200, %{banks: banks})
  end

  get "/memory-banks/:agent_name" do
    content = Shazam.SkillMemory.read_agent(agent_name)
    json(conn, 200, %{agent: agent_name, content: content})
  end

  put "/memory-banks/:agent_name" do
    %{"content" => content} = conn.body_params
    case Shazam.SkillMemory.write_agent(agent_name, content) do
      :ok -> json(conn, 200, %{status: "ok"})
      {:error, reason} -> json(conn, 422, %{error: inspect(reason)})
    end
  end

  post "/memory-banks/init" do
    case Shazam.SkillMemory.init() do
      {:ok, dir} -> json(conn, 200, %{status: "ok", directory: dir})
      {:error, reason} -> json(conn, 422, %{error: inspect(reason)})
    end
  end

  # --- Agent Budget ---

  get "/agents/:agent_name/budget" do
    case Shazam.Metrics.check_budget(agent_name) do
      :ok ->
        json(conn, 200, %{status: "ok", within_budget: true})

      {:warning, used, budget} ->
        json(conn, 200, %{
          status: "warning",
          within_budget: true,
          tokens_used: used,
          budget: budget,
          percentage: round(used / budget * 100)
        })

      {:exceeded, used, budget} ->
        json(conn, 200, %{
          status: "exceeded",
          within_budget: false,
          tokens_used: used,
          budget: budget,
          percentage: round(used / budget * 100)
        })
    end
  end

  # --- Agent Context Window ---

  get "/agents/:agent_name/context" do
    agent_data = Shazam.Metrics.get_agent(agent_name) || %{}
    context = agent_data[:context] || %{last_input: 0, last_output: 0, peak_input: 0}

    capacity = 200_000
    usage_pct = if context.last_input > 0, do: round(context.last_input / capacity * 100), else: 0

    json(conn, 200, %{
      agent: agent_name,
      last_input_tokens: context.last_input,
      last_output_tokens: context.last_output,
      peak_input_tokens: context.peak_input,
      capacity: capacity,
      usage_percent: usage_pct,
      warning: usage_pct > 80
    })
  end

  # --- Agent Inbox ---

  post "/agents/:agent_name/message" do
    message = conn.body_params["message"] || ""

    if message == "" do
      json(conn, 400, %{error: "message is required"})
    else
      Shazam.AgentInbox.push(agent_name, message)

      Shazam.API.EventBus.broadcast(%{
        event: "agent_output",
        agent: agent_name,
        type: "user_input",
        content: message
      })

      company = conn.body_params["company"] || find_first_company()
      running_tasks = if company do
        try do
          ralph_status = Shazam.RalphLoop.status(company)
          ralph_status[:running_tasks] || []
        rescue
          _ -> []
        catch
          :exit, _ -> []
        end
      else
        []
      end
      agent_busy = Enum.any?(running_tasks, fn t ->
        t[:agent] == agent_name
      end)

      if agent_busy do
        json(conn, 202, %{status: "queued", message: "Agent is busy — message queued for after current task"})
      else
        spawn(fn -> Shazam.AgentInbox.execute_pending(agent_name) end)
        json(conn, 200, %{status: "executing", message: "Executing message on agent session"})
      end
    end
  end

  # --- Agent-to-Agent Messaging ---

  post "/agents/:from_agent/message-to/:to_agent" do
    message = conn.body_params["message"]

    if !message || message == "" do
      json(conn, 400, %{error: "message is required"})
    else
      Shazam.AgentInbox.push_from_agent(to_agent, from_agent, message)

      Shazam.API.EventBus.broadcast(%{
        event: "agent_collaboration",
        from: from_agent,
        to: to_agent,
        message: String.slice(message, 0..100)
      })

      json(conn, 200, %{status: "sent", from: from_agent, to: to_agent})
    end
  end

  # --- Workspaces list ---

  get "/workspaces" do
    history = case Shazam.Store.load("workspace_history") do
      {:ok, %{"workspaces" => list}} -> list
      _ -> []
    end

    current = Application.get_env(:shazam, :workspace, nil)

    workspaces = Enum.map(history, fn ws ->
      company = ws["company"]
      company_active = if company, do: Shazam.RalphLoop.exists?(company), else: false

      ws
      |> Map.put("active", ws["path"] == current)
      |> Map.put("company_active", company_active)
    end)

    json(conn, 200, %{workspaces: workspaces})
  end

  delete "/workspaces" do
    path = conn.body_params["path"]

    history = case Shazam.Store.load("workspace_history") do
      {:ok, %{"workspaces" => list}} -> list
      _ -> []
    end

    updated = Enum.reject(history, fn ws -> ws["path"] == path end)
    Shazam.Store.save("workspace_history", %{"workspaces" => updated})
    json(conn, 200, %{status: "ok"})
  end

  # --- Config Import ---

  post "/import" do
    workspace = conn.body_params["workspace"] || Application.get_env(:shazam, :workspace, File.cwd!())
    preview = conn.body_params["preview"] == true

    case Shazam.ConfigImport.import_from_workspace(workspace) do
      {:ok, yaml} ->
        if preview do
          json(conn, 200, %{status: "preview", yaml: yaml})
        else
          case Shazam.ConfigImport.import_and_save(workspace) do
            {:ok, path, _yaml} -> json(conn, 200, %{status: "ok", path: path, yaml: yaml})
            {:error, reason} -> json(conn, 500, %{error: inspect(reason)})
          end
        end

      {:error, :no_configs_found} ->
        json(conn, 404, %{error: "No IDE config directories found (.claude/, .gemini/, .cursor/, AGENTS.md)"})

      {:error, reason} ->
        json(conn, 500, %{error: inspect(reason)})
    end
  end

  # --- Config Sync ---

  post "/sync" do
    company = conn.body_params["company"]
    providers = conn.body_params["providers"]
    preview = conn.body_params["preview"] == true

    workspace = Application.get_env(:shazam, :workspace, File.cwd!())

    {:ok, result} =
      Shazam.ConfigSync.sync(
        workspace,
        company,
        providers: providers || ["claude", "gemini", "cursor", "codex"],
        preview: preview
      )

    Shazam.AuditLog.record("config_synced", %{company: company, files: result.count})

    json(conn, 200, %{
      status: "ok",
      count: result.count,
      providers: result.providers,
      files: Enum.map(result.files, fn f -> %{path: f.path, type: f.type} end)
    })
  end

  # POST /save-subagents — save subagents config directly to shazam.yaml + sync
  post "/save-subagents" do
    workspace = Shazam.Config.global_workspace()
    subagents = conn.body_params["subagents"] || []
    agent_assignments = conn.body_params["agent_assignments"] || %{}
    company = conn.body_params["company"]

    # Save global subagents section (also removes if empty)
    if is_list(subagents) do
      case Shazam.YamlWriter.update_subagents(workspace, subagents) do
        {:ok, _} -> :ok
        {:error, reason} ->
          Logger.warning("[API] Failed to save subagents to yaml: #{inspect(reason)}")
      end
    end

    # Save per-agent subagent assignments (also removes empty ones)
    if is_map(agent_assignments) && map_size(agent_assignments) > 0 do
      case Shazam.YamlWriter.update_agent_subagents(workspace, agent_assignments) do
        {:ok, _} -> :ok
        {:error, reason} ->
          Logger.warning("[API] Failed to save agent assignments to yaml: #{inspect(reason)}")
      end
    end

    # Auto-sync after saving
    sync_result = if company do
      case Shazam.ConfigSync.sync(workspace, company) do
        {:ok, result} -> %{synced: true, files: result.count}
        _ -> %{synced: false}
      end
    else
      %{synced: false}
    end

    json(conn, 200, %{status: "ok", sync: sync_result})
  end

  get "/sync/status" do
    workspace = Application.get_env(:shazam, :workspace, File.cwd!())
    status = Shazam.ConfigSync.status(workspace)
    json(conn, 200, status)
  end

  # --- Agent Performance Scores ---

  get "/agents/:agent_name/score" do
    score = Shazam.Metrics.agent_score(agent_name)
    json(conn, 200, score)
  end

  get "/scores" do
    scores = Shazam.Metrics.all_agent_scores()
    json(conn, 200, %{scores: scores})
  end

  # --- Agent Subagents ---

  get "/agents/:agent_name/subagents" do
    workspace = Application.get_env(:shazam, :workspace, nil)
    if workspace do
      # First check YAML config
      {agents, _, _, _, _, _} = Shazam.ConfigSync.read_from_yaml(workspace)
      agent = Enum.find(agents, fn a -> (a[:name] || a["name"]) == agent_name end)
      yaml_subagents = if agent, do: agent[:subagents] || [], else: []

      # Then check overrides (takes precedence)
      override_path = Path.join(workspace, ".shazam/overrides.json")
      override_subagents = case File.read(override_path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, %{"agents" => agents_map}} ->
              case agents_map[agent_name] do
                %{"subagents" => subs} when is_list(subs) -> subs
                _ -> nil
              end
            _ -> nil
          end
        _ -> nil
      end

      subagents = override_subagents || yaml_subagents
      json(conn, 200, %{agent: agent_name, subagents: subagents})
    else
      json(conn, 200, %{agent: agent_name, subagents: []})
    end
  end

  put "/agents/:agent_name/subagents" do
    workspace = Application.get_env(:shazam, :workspace, nil)
    new_subagents = conn.body_params["subagents"] || []

    if workspace do
      # Store subagent assignments in overrides.json (same pattern as hierarchy overrides)
      override_path = Path.join(workspace, ".shazam/overrides.json")
      overrides = case File.read(override_path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, data} -> data
            _ -> %{}
          end
        _ -> %{}
      end

      agent_overrides = overrides["agents"] || %{}
      agent_data = agent_overrides[agent_name] || %{}
      agent_data = Map.put(agent_data, "subagents", new_subagents)
      agent_overrides = Map.put(agent_overrides, agent_name, agent_data)
      overrides = Map.put(overrides, "agents", agent_overrides)

      File.mkdir_p!(Path.dirname(override_path))
      File.write!(override_path, Jason.encode!(overrides, pretty: true))

      json(conn, 200, %{status: "ok", agent: agent_name, subagents: new_subagents})
    else
      json(conn, 400, %{error: "No workspace set"})
    end
  end

  match _ do
    json(conn, 404, %{error: "Not found"})
  end

  # ── Private helpers ─────────────────────
  defp build_context_tree(dir, root) do
    case File.ls(dir) do
      {:ok, entries} ->
        entries
        |> Enum.sort()
        |> Enum.map(fn entry ->
          full = Path.join(dir, entry)
          rel = Path.relative_to(full, root)
          if File.dir?(full) do
            %{name: entry, path: rel, type: "directory", children: build_context_tree(full, root)}
          else
            %{name: entry, path: rel, type: "file", children: []}
          end
        end)
      _ -> []
    end
  end
end
