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

  # --- Config ---

  get "/config" do
    company = try do
      Registry.select(Shazam.CompanyRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
      |> List.first()
      |> to_string()
    catch
      _, _ -> nil
    end

    ralph_config = if company do
      try do
        status = Shazam.RalphLoop.status(company)
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

    json(conn, 200, %{
      company: company,
      ralph_loop: ralph_config,
      workspace: workspace,
      provider: to_string(Application.get_env(:shazam, :default_provider, "claude_code")),
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

    json(conn, 200, %{
      status: "ok",
      version: "0.2.5",
      workspace: workspace,
      memory_mb: memory_mb,
      companies: companies,
      pid: pid,
      port: port
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
end
