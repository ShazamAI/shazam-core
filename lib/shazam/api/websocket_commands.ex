defmodule Shazam.API.WebSocketCommands do
  @moduledoc """
  Handles TUI commands received over WebSocket in daemon mode.
  Returns a list of messages to push back to the client.

  Helpers (event_msg, list_tasks, etc.) are in WebSocketCommands.Helpers.
  """

  import Shazam.API.WebSocketCommands.Helpers

  @doc "Dispatches a TUI command string and returns a list of response messages."
  def handle(command, conn_state) do
    company = conn_state[:company]
    workspace = conn_state[:workspace]
    _agents = conn_state[:agents] || []
    _ = workspace
    raw = String.trim(command)

    cond do
      raw == "/start" ->
        handle_start(conn_state)

      raw == "/stop" ->
        handle_stop(company)

      raw == "/resume" ->
        handle_resume(company)

      raw == "/status" ->
        [build_status(conn_state)]

      raw == "/dashboard" ->
        [build_dashboard(conn_state)]

      raw == "/tasks" ->
        [build_task_list(company)]

      raw == "/agents" ->
        [build_agent_list(conn_state)]

      raw == "/health" ->
        [build_health(company)]

      String.starts_with?(raw, "/task ") ->
        handle_create_task(raw, conn_state)

      String.starts_with?(raw, "/approve ") ->
        task_id = String.trim_leading(raw, "/approve ") |> String.trim()
        Shazam.TaskBoard.approve(task_id)
        [event_msg("system", "task_approved", task_id), build_status(conn_state)]

      raw in ["/aa", "/approve-all"] ->
        handle_approve_all(company, conn_state)

      String.starts_with?(raw, "/reject ") ->
        task_id = String.trim_leading(raw, "/reject ") |> String.trim()
        Shazam.TaskBoard.reject(task_id)
        [event_msg("system", "task_rejected", task_id), build_status(conn_state)]

      String.starts_with?(raw, "/kill-task ") ->
        task_id = String.trim_leading(raw, "/kill-task ") |> String.trim()
        Shazam.TaskBoard.fail(task_id, "Killed by user")
        [event_msg("system", "task_killed", task_id), build_status(conn_state)]

      String.starts_with?(raw, "/retry-task ") ->
        task_id = String.trim_leading(raw, "/retry-task ") |> String.trim()
        Shazam.TaskBoard.retry(task_id)
        [event_msg("system", "info", "Retrying #{task_id}"), build_status(conn_state)]

      raw == "/retry-all" ->
        handle_retry_all(company, conn_state)

      String.starts_with?(raw, "/delete-task ") ->
        task_id = String.trim_leading(raw, "/delete-task ") |> String.trim()
        Shazam.TaskBoard.delete(task_id)
        [event_msg("system", "info", "Deleted #{task_id}"), build_status(conn_state)]

      String.starts_with?(raw, "/pause-task ") ->
        task_id = String.trim_leading(raw, "/pause-task ") |> String.trim()
        Shazam.TaskBoard.pause(task_id)
        [event_msg("system", "task_paused", task_id), build_status(conn_state)]

      String.starts_with?(raw, "/resume-task ") ->
        task_id = String.trim_leading(raw, "/resume-task ") |> String.trim()
        Shazam.TaskBoard.resume_task(task_id)
        [event_msg("system", "task_resumed", task_id), build_status(conn_state)]

      String.starts_with?(raw, "/msg ") ->
        handle_msg(raw, conn_state)

      raw == "/tasks --clear" ->
        Shazam.TaskBoard.clear_all()
        [event_msg("system", "info", "All tasks cleared"), build_status(conn_state)]

      raw == "/tasks --sync" ->
        try do
          Shazam.TaskFiles.sync_from_files()
          [event_msg("system", "info", "Tasks synced from files")]
        catch
          _, _ -> [event_msg("system", "error", "Sync failed")]
        end

      raw == "/restart" ->
        handle_stop(company) ++ handle_start(conn_state)

      raw == "/reload" ->
        case Shazam.HotReload.reload() do
          {:ok, result} ->
            [event_msg("system", "info", "Hot reload: #{result.reloaded} modules reloaded in #{result.elapsed_ms}ms (zero downtime)")]
          {:error, reason} ->
            [event_msg("system", "error", "Reload failed: #{inspect(reason)}")]
        end

      raw == "/auto-approve" ->
        current = try do
          Shazam.RalphLoop.status(company)[:auto_approve] || false
        catch
          _, _ -> false
        end
        new_val = !current
        try do
          Shazam.RalphLoop.set_auto_approve(company, new_val)
        catch
          _, _ -> :ok
        end
        [event_msg("system", "info", "Auto-approve: #{new_val} (session only)")]

      String.starts_with?(raw, "/search ") ->
        query = String.trim_leading(raw, "/search ") |> String.trim() |> String.downcase()
        tasks = list_tasks(company)
        matches = Enum.filter(tasks, fn t ->
          String.contains?(String.downcase(t.title || ""), query)
        end)
        if matches == [] do
          [event_msg("system", "info", "No tasks matching '#{query}'")]
        else
          Enum.map(matches, fn t ->
            event_msg("system", "info", "  #{t.id}: [#{t.status}] #{t.title}")
          end)
        end

      raw == "/quit" || raw == "/exit" ->
        [%{type: "quit"}]

      raw == "/clear" ->
        [%{type: "clear"}]

      raw == "/config" ->
        [build_config(conn_state)]

      raw == "/org" ->
        handle_org(conn_state)

      raw == "/plugins" ->
        handle_plugins(conn_state)

      raw == "/plugins reload" ->
        handle_plugins_reload(workspace, conn_state)

      String.starts_with?(raw, "/plan ") ->
        handle_plan(raw, conn_state)

      raw == "/memory" ->
        handle_memory(conn_state)

      raw == "/workspaces" ->
        handle_workspaces(conn_state)

      String.starts_with?(raw, "/github sync") ->
        handle_github_sync(conn_state)

      String.starts_with?(raw, "/qa") ->
        handle_qa(raw, conn_state)

      String.starts_with?(raw, "/start-task ") ->
        task_id = String.trim_leading(raw, "/start-task ") |> String.trim()
        Shazam.TaskBoard.approve(task_id)
        [event_msg("system", "info", "Task #{task_id} started"), build_status(conn_state)]

      String.starts_with?(raw, "/export") ->
        handle_export(company)

      String.starts_with?(raw, "/review ") || raw == "/review" ->
        [event_msg("system", "info", "PR review requires inline mode. Run: shazam daemon stop && shazam")]

      raw == "/knowledge" || raw == "/knowledge --update" ->
        [event_msg("system", "info", "Knowledge bank requires inline mode.")]

      String.starts_with?(raw, "/plugins install ") || String.starts_with?(raw, "/plugins remove ") ->
        [event_msg("system", "info", "Plugin install/remove requires inline mode.")]

      String.starts_with?(raw, "/agent ") || raw == "/agents --init" ->
        [event_msg("system", "info", "Agent management: edit shazam.yaml directly.")]

      String.starts_with?(raw, "/team ") ->
        [event_msg("system", "info", "Team management: edit shazam.yaml directly.")]

      raw == "/help" ->
        [event_msg("system", "info", help_text())]

      true ->
        if String.starts_with?(raw, "/") do
          [event_msg("system", "error", "Unknown command: #{raw}. Type /help for commands.")]
        else
          handle_create_task("/task " <> raw, conn_state)
        end
    end
  rescue
    e -> [event_msg("system", "error", "Command error: #{inspect(e)}")]
  catch
    _, reason -> [event_msg("system", "error", "Command error: #{inspect(reason)}")]
  end

  # ── Command Handlers ──────────────────────────────────

  defp handle_start(conn_state) do
    company = conn_state[:company]
    config = conn_state[:config] || %{}
    agents = conn_state[:agents] || []

    # Check if company is already running — if so, just resume, don't recreate
    already_running = try do
      case Registry.lookup(Shazam.CompanyRegistry, company) do
        [{_, _}] -> true
        _ -> false
      end
    catch
      _, _ -> false
    end

    if already_running do
      # Just resume RalphLoop if paused
      if Shazam.RalphLoop.exists?(company) do
        Shazam.RalphLoop.resume(company)
      end
      [event_msg("system", "info", "Company '#{company}' ready"), build_status(conn_state)]
    else
      # Not running — start via ProjectRegistry (reads YAML with full agent data)
      case Shazam.ProjectRegistry.start_project(company) do
        {:ok, _} ->
          [event_msg("system", "company_started", "Company '#{company}' started"), build_status(conn_state)]
        {:error, _} ->
          # Fallback: start with config from WebSocket subscribe (TUI mode)
          handle_start_with_config(company, config, agents, conn_state)
      end
    end
  end

  defp handle_start_with_config(company, config, agents, conn_state) do
    # Double-check: if company is already running, don't recreate
    already_exists = try do
      case Registry.lookup(Shazam.CompanyRegistry, company) do
        [{_, _}] -> true
        _ -> false
      end
    catch
      _, _ -> false
    end

    if already_exists do
      if Shazam.RalphLoop.exists?(company), do: Shazam.RalphLoop.resume(company)
      return_msgs = [event_msg("system", "info", "Company '#{company}' ready"), build_status(conn_state)]
      return_msgs
    else
      do_start_with_config(company, config, agents, conn_state)
    end
  end

  defp do_start_with_config(company, config, agents, conn_state) do
    if config[:provider] do
      Application.put_env(:shazam, :default_provider, config[:provider])
    end

    company_config = %{
      name: company,
      mission: config[:mission] || "",
      agents: agents,
      domain_config: config[:domain_config] || %{}
    }

    result = case Shazam.start_company(company_config) do
      {:ok, _} ->
        event_msg("system", "company_started", "Company '#{company}' started — #{length(agents)} agent(s)")
      {:error, {:already_started, _}} ->
        # Only update agents if we actually have agent data (don't overwrite with empty)
        if agents != [] && Enum.any?(agents, fn a -> a[:name] end) do
          try do
            Shazam.Company.update_agents(company, agents)
          catch
            _, _ -> :ok
          end
        end
        event_msg("system", "info", "Company '#{company}' ready (#{length(agents)} agents)")
      {:error, reason} ->
        event_msg("system", "error", "Failed to start company: #{inspect(reason)}")
    end

    # Wait for RalphLoop
    wait_for_ralph(company, 15)

    # Apply config
    if Shazam.RalphLoop.exists?(company) do
      try do
        rc = config[:ralph_config] || %{}
        if rc[:auto_approve], do: Shazam.RalphLoop.set_auto_approve(company, true)
        if rc[:max_concurrent], do: Shazam.RalphLoop.set_config(company, "max_concurrent", rc[:max_concurrent])
        if rc[:qa_auto], do: Application.put_env(:shazam, :qa_auto, true)
        if rc[:qa_routing], do: Application.put_env(:shazam, :qa_routing, true)
      catch
        _, _ -> :ok
      end

      Shazam.RalphLoop.resume(company)
    end

    [result, build_status(conn_state)]
  end

  defp handle_stop(company) do
    if company && Shazam.RalphLoop.exists?(company) do
      Shazam.RalphLoop.pause(company)
      [event_msg("system", "ralph_paused", "Agents stopped")]
    else
      [event_msg("system", "info", "No agents running")]
    end
  end

  defp handle_resume(company) do
    if company && Shazam.RalphLoop.exists?(company) do
      Shazam.RalphLoop.resume(company)
      [event_msg("system", "ralph_resumed", "Agents resumed")]
    else
      [event_msg("system", "error", "No company started. Use /start first.")]
    end
  end

  defp handle_create_task(raw, conn_state) do
    title = String.trim_leading(raw, "/task ") |> String.trim()
    company = conn_state[:company]
    pm_name = find_pm_name(conn_state[:agents] || [])

    Shazam.TaskBoard.create(%{
      title: title,
      assigned_to: pm_name,
      created_by: "human",
      company: company,
      description: title
    })

    [event_msg(pm_name, "task_created", title), build_status(conn_state)]
  end

  defp handle_approve_all(company, conn_state) do
    tasks = list_tasks(company)
    pending = Enum.filter(tasks, &(to_string(&1.status) == "awaiting_approval"))

    Enum.each(pending, fn t ->
      Shazam.TaskBoard.approve(t.id)
    end)

    count = length(pending)
    [event_msg("system", "info", "Approved #{count} task(s)"), build_status(conn_state)]
  end

  defp handle_msg(raw, _conn_state) do
    rest = String.trim_leading(raw, "/msg ") |> String.trim()
    case String.split(rest, " ", parts: 2) do
      [agent_name, message] ->
        try do
          Shazam.AgentInbox.push(agent_name, message)
          [event_msg("system", "info", "Message sent to #{agent_name}")]
        catch
          _, _ -> [event_msg("system", "error", "Failed to send message")]
        end
      _ ->
        [event_msg("system", "error", "Usage: /msg <agent> <message>")]
    end
  end

  defp handle_org(conn_state) do
    agents = conn_state[:agents] || []
    if agents == [] do
      [event_msg("system", "info", "No agents configured")]
    else
      lines = Enum.map(agents, fn a ->
        name = a[:name] || "?"
        role = a[:role] || ""
        sup = a[:supervisor]
        prefix = if sup, do: "  └── ", else: ""
        event_msg("system", "info", "#{prefix}#{name} (#{role})")
      end)
      [event_msg("system", "info", "Organization:")] ++ lines
    end
  end

  defp handle_memory(conn_state) do
    agents = conn_state[:agents] || []
    memory_mb = div(:erlang.memory(:total), 1_048_576)

    lines = [event_msg("system", "info", "Memory: #{memory_mb}MB (BEAM)")]

    agent_lines = Enum.map(agents, fn a ->
      name = a[:name] || ""
      metrics = try do
        Shazam.Metrics.get_agent(name) || %{}
      catch
        _, _ -> %{}
      end
      tokens = Map.get(metrics, :tokens_used, 0)
      cost = Map.get(metrics, :estimated_cost, 0.0)
      event_msg("system", "info", "  #{name}: #{tokens} tokens ($#{Float.round(cost * 1.0, 4)})")
    end)

    total_cost = try do
      case Shazam.Metrics.get_all() do
        %{totals: %{estimated_cost: c}} when is_number(c) -> c
        _ -> 0.0
      end
    catch
      _, _ -> 0.0
    end

    lines ++ agent_lines ++ [event_msg("system", "info", "  Total: $#{Float.round(total_cost * 1.0, 4)}")]
  end

  defp handle_workspaces(conn_state) do
    workspaces = Application.get_env(:shazam, :workspaces, %{})
    if workspaces == nil or workspaces == %{} do
      workspace = conn_state[:workspace] || "N/A"
      [event_msg("system", "info", "Workspace: #{workspace}")]
    else
      lines = Enum.map(workspaces, fn {name, config} ->
        path = if is_map(config), do: config[:path] || config["path"] || "", else: ""
        exists = if File.dir?(path), do: "✓", else: "✗"
        event_msg("system", "info", "  #{exists} #{name}: #{path}")
      end)
      [event_msg("system", "info", "Workspaces:")] ++ lines
    end
  end

  defp handle_github_sync(conn_state) do
    try do
      Shazam.PluginManager.notify(:on_init, %{
        company_name: conn_state[:company],
        plugin_config: %{}
      })
      [event_msg("system", "info", "GitHub sync triggered")]
    catch
      _, _ -> [event_msg("system", "error", "GitHub sync failed")]
    end
  end

  defp handle_qa(raw, conn_state) do
    args = String.trim_leading(raw, "/qa") |> String.trim()
    _company = conn_state[:company]

    cond do
      args == "" ->
        # List QA docs
        workspace = conn_state[:workspace] || "."
        qa_dir = Path.join(workspace, ".shazam/qa")
        if File.dir?(qa_dir) do
          files = File.ls!(qa_dir) |> Enum.filter(&String.ends_with?(&1, ".md")) |> Enum.sort()
          if files == [] do
            [event_msg("system", "info", "No QA docs found")]
          else
            Enum.map(files, fn f ->
              event_msg("system", "info", "  #{f}")
            end)
          end
        else
          [event_msg("system", "info", "No QA docs found")]
        end

      String.starts_with?(args, "--auto ") ->
        val = String.trim_leading(args, "--auto ") |> String.trim()
        enabled = val in ["on", "true", "1"]
        Application.put_env(:shazam, :qa_auto, enabled)
        [event_msg("system", "info", "QA auto: #{enabled} (session only)")]

      String.starts_with?(args, "--generate ") ->
        task_id = String.trim_leading(args, "--generate ") |> String.trim()
        try do
          case Shazam.TaskBoard.get(task_id) do
            {:ok, task} ->
              case Shazam.QAManager.generate_qa_doc(task) do
                {:ok, path} -> [event_msg("system", "info", "QA doc generated: #{path}")]
                _ -> [event_msg("system", "error", "QA generation failed")]
              end
            _ -> [event_msg("system", "error", "Task #{task_id} not found")]
          end
        catch
          _, _ -> [event_msg("system", "error", "QA generation failed")]
        end

      true ->
        [event_msg("system", "error", "Usage: /qa, /qa --generate <id>, /qa --auto on|off")]
    end
  end

  defp handle_export(company) do
    tasks = list_tasks(company)
    if tasks == [] do
      [event_msg("system", "info", "No tasks to export")]
    else
      lines = Enum.map(tasks, fn t ->
        "- [#{t.status}] #{t.title} (#{t.assigned_to || "unassigned"})"
      end)
      [event_msg("system", "info", "Tasks:\n#{Enum.join(lines, "\n")}")]
    end
  end

  defp handle_retry_all(company, conn_state) do
    tasks = list_tasks(company)
    failed = Enum.filter(tasks, &(to_string(&1.status) == "failed"))

    Enum.each(failed, fn t ->
      Shazam.TaskBoard.retry(t.id)
    end)

    [event_msg("system", "info", "Retrying #{length(failed)} task(s)"), build_status(conn_state)]
  end

  defp handle_plugins(_conn_state) do
    plugins = try do
      Shazam.PluginManager.list_plugins()
    catch
      _, _ -> []
    end

    if plugins == [] do
      [event_msg("system", "info", "No plugins loaded")]
    else
      msgs = Enum.map(plugins, fn p ->
        event_msg("system", "info", "  #{p.name} — #{p.events || "all events"}")
      end)
      [event_msg("system", "info", "Loaded plugins:")] ++ msgs
    end
  end

  defp handle_plugins_reload(_workspace, _conn_state) do
    try do
      Shazam.PluginManager.reload()
      [event_msg("system", "info", "Plugins reloaded")]
    catch
      _, e -> [event_msg("system", "error", "Plugin reload failed: #{inspect(e)}")]
    end
  end

  defp handle_plan(raw, conn_state) do
    description = String.trim_leading(raw, "/plan ") |> String.trim()
    company = conn_state[:company]
    pm_name = find_pm_name(conn_state[:agents] || [])

    cond do
      description == "--list" ->
        plans = Shazam.PlanManager.list_plans()
        if plans == [] do
          [event_msg("system", "info", "No plans found")]
        else
          Enum.map(plans, fn p ->
            event_msg("system", "info", "  #{p.id}: [#{p.status}] #{p.title} (#{length(p.tasks)} tasks)")
          end)
        end

      String.starts_with?(description, "--approve ") ->
        plan_id = String.trim_leading(description, "--approve ") |> String.trim()
        case Shazam.PlanManager.read_plan(plan_id) do
          {:ok, plan} ->
            case Shazam.PlanManager.create_tasks_from_plan(plan, company) do
              {:ok, count} ->
                [event_msg("system", "info", "Plan '#{plan.title}' approved — #{count} tasks created")]
              {:error, reason} ->
                [event_msg("system", "error", "Failed: #{inspect(reason)}")]
            end
          {:error, _} ->
            [event_msg("system", "error", "Plan #{plan_id} not found")]
        end

      String.starts_with?(description, "--show ") ->
        plan_id = String.trim_leading(description, "--show ") |> String.trim()
        case Shazam.PlanManager.read_plan(plan_id) do
          {:ok, plan} ->
            header = event_msg("system", "info", "Plan: #{plan.title} [#{plan.status}]")
            task_msgs = plan.tasks
              |> Enum.group_by(fn t -> t[:phase] || "Tasks" end)
              |> Enum.flat_map(fn {phase, tasks} ->
                [event_msg("system", "info", "  #{phase}:")] ++
                Enum.map(tasks, fn t ->
                  agent = t[:assigned_to] || "unassigned"
                  event_msg("system", "info", "    - #{t.title} → #{agent}")
                end)
              end)
            [header | task_msgs]
          {:error, _} ->
            [event_msg("system", "error", "Plan #{plan_id} not found")]
        end

      true ->
        prompt = Shazam.PlanManager.build_plan_prompt(description)
        plan_id = Shazam.PlanManager.next_id()
        short_desc = String.slice(description, 0..80)

        Shazam.TaskBoard.create(%{
          title: "Create plan: #{short_desc}",
          assigned_to: pm_name,
          created_by: "human",
          company: company,
          description: prompt <> "\n\nPlan ID: #{plan_id}"
        })

        [event_msg(pm_name, "task_created", "Planning: #{short_desc}"),
         event_msg("system", "info", "When done: /plan --show #{plan_id} → /plan --approve #{plan_id}")]
    end
  end

  # ── Builders ──────────────────────────────────────────

  @doc "Builds a status snapshot map for the TUI dashboard."
  def build_status(conn_state) do
    company = conn_state[:company] || ""
    workspace = conn_state[:workspace]

    # Get agents from the actual Company GenServer, not from conn_state (which may be empty)
    agents = try do
      case Registry.lookup(Shazam.CompanyRegistry, company) do
        [{pid, _}] ->
          state = :sys.get_state(pid)
          state.agents || []
        _ -> conn_state[:agents] || []
      end
    catch
      _, _ -> conn_state[:agents] || []
    end

    {pending, running, done, awaiting} = get_task_counts(company)

    agents_total = length(agents)
    agents_active = try do
      if Shazam.RalphLoop.exists?(company) do
        case Shazam.RalphLoop.status(company) do
          %{running_count: n} when is_integer(n) -> n
          _ -> 0
        end
      else
        0
      end
    catch
      _, _ -> 0
    end

    total_cost = try do
      case Shazam.Metrics.get_all() do
        %{totals: %{estimated_cost: cost}} when is_number(cost) -> cost
        _ -> 0.0
      end
    catch
      _, _ -> 0.0
    end

    budget_total = agents |> Enum.map(& &1[:budget] || 100_000) |> Enum.sum()
    budget_used = try do
      agents |> Enum.reduce(0, fn a, acc ->
        name = a[:name] || to_string(a[:name])
        case Shazam.Metrics.get_agent(name) do
          %{tokens_used: t} when is_integer(t) -> acc + t
          _ -> acc
        end
      end)
    catch
      _, _ -> 0
    end

    sparklines = try do
      Shazam.AgentPulse.all_sparklines()
    catch
      _, _ -> %{}
    end

    git_branch = try do
      Shazam.GitContext.current_branch(workspace)
    catch
      _, _ -> ""
    end

    git_status = try do
      case Shazam.GitContext.modified_files(workspace) do
        [] -> "clean"
        files when is_list(files) -> "#{length(files)} modified"
      end
    catch
      _, _ -> ""
    end

    provider = to_string(Application.get_env(:shazam, :default_provider, "claude_code"))
    memory_mb = div(:erlang.memory(:total), 1_048_576)

    %{
      type: "status",
      company: company,
      status: get_ralph_status(company),
      agents_total: agents_total,
      agents_active: agents_active,
      tasks_pending: pending,
      tasks_running: running,
      tasks_done: done,
      tasks_awaiting: awaiting,
      budget_used: budget_used,
      budget_total: budget_total,
      memory_mb: memory_mb,
      sparklines: sparklines,
      total_cost: total_cost,
      git_branch: git_branch,
      git_status: git_status,
      provider: provider
    }
  end

  defp build_dashboard(conn_state) do
    agents = conn_state[:agents] || []
    company = conn_state[:company]

    agent_data = Enum.map(agents, fn agent ->
      name = agent[:name] || ""
      metrics = try do
        Shazam.Metrics.get_agent(name) || %{}
      catch
        _, _ -> %{}
      end

      current_task = try do
        tasks = list_tasks(company)
        case Enum.find(tasks, &(&1.assigned_to == name && to_string(&1.status) in ["in_progress", "running"])) do
          nil -> nil
          t -> t.title
        end
      catch
        _, _ -> nil
      end

      %{
        name: name,
        role: agent[:role],
        status: Map.get(metrics, :status, "idle"),
        tasks_completed: Map.get(metrics, :tasks_completed, 0),
        tasks_failed: Map.get(metrics, :tasks_failed, 0),
        tokens_used: Map.get(metrics, :tokens_used, 0),
        budget: agent[:budget],
        current_task: current_task
      }
    end)

    %{type: "dashboard", agents: agent_data}
  end

  defp build_task_list(company) do
    tasks = list_tasks(company)
      |> Enum.map(fn t ->
        %{
          id: t.id,
          title: t.title || "",
          status: to_string(t.status),
          assigned_to: t.assigned_to || "",
          created_by: t.created_by || "",
          result: if(is_binary(t.result), do: String.slice(t.result, 0..2000), else: "")
        }
      end)

    %{type: "task_list", tasks: tasks}
  end

  defp build_agent_list(conn_state) do
    agents = conn_state[:agents] || []

    agent_data = Enum.map(agents, fn a ->
      name = a[:name] || ""
      %{
        name: name,
        role: a[:role] || "",
        supervisor: a[:supervisor],
        workspace: a[:workspace],
        provider: a[:provider]
      }
    end)

    %{type: "agent_list", agents: agent_data}
  end

  defp build_config(conn_state) do
    company = conn_state[:company] || "N/A"
    config = conn_state[:config] || %{}

    entries = [
      "Provider: #{config[:provider] || "claude_code"}",
      "Agents: #{length(conn_state[:agents] || [])}",
      "Workspace: #{conn_state[:workspace] || "N/A"}",
      "Auto-approve: #{get_in(config, [:ralph_config, :auto_approve]) || false}",
      "QA routing: #{get_in(config, [:ralph_config, :qa_routing]) || false}"
    ]

    %{
      type: "config",
      company: company,
      mission: config[:mission] || "",
      entries: entries
    }
  end

  defp build_health(company) do
    ralph_status = get_ralph_status(company)
    memory_mb = div(:erlang.memory(:total), 1_048_576)

    circuit_state = try do
      if Shazam.CircuitBreaker.tripped?(), do: "TRIPPED", else: "ok"
    catch
      _, _ -> "unknown"
    end

    event_msg("system", "info",
      "Health: ralph=#{ralph_status} | circuit=#{circuit_state} | mem=#{memory_mb}MB")
  end

end
