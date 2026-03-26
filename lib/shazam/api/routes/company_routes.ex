defmodule Shazam.API.Routes.CompanyRoutes do
  @moduledoc "Handles all /api/companies/* endpoints."

  use Plug.Router

  import Shazam.API.Helpers

  plug :match
  plug :dispatch

  post "/" do
    %{"name" => name, "mission" => mission, "agents" => agents_raw} = conn.body_params

    agents = Enum.map(agents_raw, fn a ->
      %{
        name: a["name"],
        role: a["role"],
        supervisor: a["supervisor"],
        domain: a["domain"],
        budget: a["budget"] || 100_000,
        heartbeat_interval: (a["heartbeat_interval"] || 60) * 1000,
        tools: a["tools"] || [],
        skills: a["skills"] || [],
        modules: a["modules"] || [],
        system_prompt: a["system_prompt"],
        model: a["model"],
        fallback_model: a["fallback_model"]
      }
    end)

    case Shazam.start_company(%{name: name, mission: mission, agents: agents}) do
      {:ok, _pid} ->
        workspace = Application.get_env(:shazam, :workspace, nil)
        if workspace, do: update_workspace_company(workspace, name)
        json(conn, 201, %{status: "ok", company: name})

      {:error, reason} ->
        json(conn, 422, %{error: inspect(reason)})
    end
  end

  get "/" do
    keys = Shazam.Store.list_keys("company:")

    ws_history = case Shazam.Store.load("workspace_history") do
      {:ok, %{"workspaces" => list}} -> list
      _ -> []
    end
    ws_by_company = Enum.reduce(ws_history, %{}, fn ws, acc ->
      case ws["company"] do
        nil -> acc
        company -> Map.put(acc, company, ws["path"])
      end
    end)

    companies = Enum.map(keys, fn key ->
      name = String.replace_prefix(key, "company:", "")
      active = Shazam.RalphLoop.exists?(name)
      workspace = Map.get(ws_by_company, name)
      %{name: name, active: active, workspace: workspace}
    end)
    json(conn, 200, %{companies: companies})
  end

  get "/:name" do
    try do
      info = Shazam.company_info(name)
      json(conn, 200, info)
    rescue
      _ -> json(conn, 404, %{error: "Company not found"})
    end
  end

  get "/:name/org-chart" do
    try do
      chart = Shazam.org_chart(name)
      json(conn, 200, %{org_chart: chart})
    rescue
      _ -> json(conn, 404, %{error: "Company not found"})
    end
  end

  get "/:name/domain-config" do
    try do
      config = Shazam.Company.get_domain_config(name)
      json(conn, 200, %{domain_config: config})
    rescue
      _ -> json(conn, 404, %{error: "Company not found"})
    end
  end

  put "/:name/domain-config" do
    domain = conn.body_params["domain"]
    paths = conn.body_params["allowed_paths"]

    try do
      :ok = Shazam.Company.set_domain_paths(name, domain, paths)
      json(conn, 200, %{status: "ok", domain: domain, allowed_paths: paths})
    rescue
      e -> json(conn, 422, %{error: inspect(e, limit: 200)})
    end
  end

  get "/:name/statuses" do
    try do
      statuses = Shazam.statuses(name)

      running_agents =
        try do
          info = Shazam.RalphLoop.status(name)
          info.running_tasks |> Enum.map(& &1.agent) |> MapSet.new()
        rescue
          _ -> MapSet.new()
        catch
          :exit, _ -> MapSet.new()
        end

      merged = Enum.map(statuses, fn agent ->
        if MapSet.member?(running_agents, agent.name) do
          %{agent | status: :working}
        else
          agent
        end
      end)

      json(conn, 200, %{agents: merged})
    rescue
      _ -> json(conn, 404, %{error: "Company not found"})
    end
  end

  get "/:name/agents" do
    try do
      agents = Shazam.Company.get_agents_full(name)
      json(conn, 200, %{agents: agents})
    rescue
      _ -> json(conn, 404, %{error: "Company not found"})
    end
  end

  put "/:name/agents" do
    %{"agents" => agents_raw} = conn.body_params

    try do
      :ok = Shazam.Company.update_agents(name, agents_raw)
      json(conn, 200, %{status: "ok"})
    rescue
      _ -> json(conn, 422, %{error: "Failed to update agents"})
    end
  end

  # Update a single agent's field (e.g., supervisor for hierarchy changes)
  put "/:name/agents/:agent_name" do
    updates = conn.body_params

    try do
      company_pid = case Registry.lookup(Shazam.CompanyRegistry, name) do
        [{pid, _}] -> pid
        _ -> nil
      end

      if company_pid do
        # Get current agents, update the target one
        state = :sys.get_state(company_pid)
        updated_agents = Enum.map(state.agents, fn agent ->
          if agent.name == agent_name do
            agent
            |> maybe_update(:supervisor, updates["supervisor"])
            |> maybe_update(:role, updates["role"])
            |> maybe_update(:domain, updates["domain"])
            |> maybe_update(:budget, updates["budget"])
            |> maybe_update(:model, updates["model"])
            |> maybe_update(:provider, updates["provider"])
            |> maybe_update(:fallback_model, updates["fallback_model"])
            |> maybe_update(:tools, updates["tools"])
            |> maybe_update(:skills, updates["skills"])
            |> maybe_update(:modules, updates["modules"])
            |> maybe_update(:system_prompt, updates["system_prompt"])
            |> maybe_update(:heartbeat_interval, updates["heartbeat_interval"])
          else
            agent
          end
        end)

        Shazam.Company.update_agents(name, updated_agents)

        # Save override to workspace
        workspace = Application.get_env(:shazam, :workspace)
        if workspace do
          save_override(workspace, agent_name, updates)
        end

        json(conn, 200, %{ok: true})
      else
        json(conn, 404, %{error: "Company not found"})
      end
    rescue
      e -> json(conn, 422, %{error: inspect(e)})
    end
  end

  post "/:name/agents/add" do
    body = conn.body_params

    agent_config = case body["preset_id"] do
      nil ->
        body

      preset_id ->
        case Shazam.AgentPresets.build(preset_id, body) do
          {:ok, config} -> config
          {:error, :preset_not_found} ->
            conn |> json(422, %{error: "Preset '#{preset_id}' not found"}) |> halt()
            nil
        end
    end

    if agent_config do
      try do
        current_agents = Shazam.Company.get_agents_full(name)

        new_name = agent_config["name"]
        if Enum.any?(current_agents, fn a -> a.name == new_name end) do
          json(conn, 422, %{error: "Agent '#{new_name}' already exists"})
        else
          agents_raw = Enum.map(current_agents, fn a ->
            %{
              "name" => a.name, "role" => a.role, "supervisor" => a.supervisor,
              "domain" => a.domain, "budget" => a.budget,
              "heartbeat_interval" => a.heartbeat_interval,
              "tools" => a.tools, "skills" => a.skills || [],
              "modules" => a.modules || [],
              "system_prompt" => a.system_prompt, "model" => a.model,
              "fallback_model" => a.fallback_model
            }
          end)

          :ok = Shazam.Company.update_agents(name, agents_raw ++ [agent_config])
          Shazam.API.EventBus.broadcast(%{event: "agent_added", agent: new_name})
          json(conn, 201, %{status: "ok", agent: agent_config})
        end
      rescue
        e -> json(conn, 422, %{error: "Failed to add agent: #{inspect(e, limit: 200)}"})
      end
    end
  end

  post "/:name/tasks" do
    %{"title" => title} = conn.body_params
    description = conn.body_params["description"]
    to = conn.body_params["assigned_to"]
    depends_on = conn.body_params["depends_on"]

    case Shazam.assign(name, title, description: description, to: to, depends_on: depends_on) do
      {:ok, task} ->
        Shazam.API.EventBus.broadcast(%{event: "task_created", task: serialize_task(task)})
        json(conn, 201, serialize_task(task))

      {:error, reason} ->
        json(conn, 422, %{error: inspect(reason)})
    end
  end

  delete "/:name" do
    try do
      Shazam.stop_company(name)
      json(conn, 200, %{status: "stopped"})
    rescue
      _ -> json(conn, 404, %{error: "Company not found"})
    end
  end

  match _ do
    json(conn, 404, %{error: "Not found"})
  end

  # ── Helpers ─────────────────────────────────────

  defp maybe_update(agent, _field, nil), do: agent
  defp maybe_update(agent, field, value), do: Map.put(agent, field, value)

  defp save_override(workspace, agent_name, updates) do
    override_path = Path.join(workspace, ".shazam/overrides.json")
    File.mkdir_p!(Path.dirname(override_path))

    existing = case File.read(override_path) do
      {:ok, content} -> Jason.decode!(content)
      _ -> %{}
    end

    agent_overrides = Map.get(existing, "agents", %{})
    current = Map.get(agent_overrides, agent_name, %{})
    merged = Map.merge(current, updates)
    agent_overrides = Map.put(agent_overrides, agent_name, merged)
    updated = Map.put(existing, "agents", agent_overrides)

    File.write!(override_path, Jason.encode!(updated, pretty: true))
  rescue
    _ -> :ok
  end
end
