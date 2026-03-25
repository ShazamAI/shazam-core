defmodule Shazam.API.Routes.MiscRoutes do
  @moduledoc "Handles sessions, metrics, agent inbox, health, presets, and templates. Forwarded with prefix /api stripped."

  use Plug.Router

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
      _, _ -> nil
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
        _, _ -> %{}
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
        _, _ -> %{}
      end
    else
      %{}
    end

    # Build domains from company domain_config
    domains = if company_name do
      try do
        Shazam.Company.get_domain_config(company_name) || %{}
      catch
        _, _ -> %{}
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
      _, _ -> []
    end

    # Get mission from company info
    {mission, company_info_workspace} = if company_name do
      try do
        info = Shazam.Company.info(company_name)
        {info[:mission], info[:workspace]}
      catch
        _, _ -> {nil, nil}
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
      _, _ -> nil
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

  # --- Events ---

  get "/events/recent" do
    # Return recent events from the EventBus buffer (last 50)
    events = try do
      Shazam.API.EventBus.recent_events()
    catch
      _, _ -> []
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

  # --- Hot Reload ---

  post "/daemon/reload" do
    case Shazam.HotReload.reload() do
      {:ok, result} ->
        json(conn, 200, result)
      {:error, reason} ->
        json(conn, 500, %{error: inspect(reason)})
    end
  end

  # --- Health ---

  get "/health" do
    workspace = Application.get_env(:shazam, :workspace, nil)
    memory_mb = div(:erlang.memory(:total), 1_048_576)

    companies = try do
      Registry.select(Shazam.CompanyRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
      |> Enum.map(&to_string/1)
    rescue
      _ -> []
    catch
      _, _ -> []
    end

    pid = to_string(:os.getpid())
    port = Application.get_env(:shazam, :port, 4040)

    circuit_breaker_tripped = try do
      Shazam.CircuitBreaker.tripped?()
    catch
      _, _ -> false
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
