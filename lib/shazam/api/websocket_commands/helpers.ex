defmodule Shazam.API.WebSocketCommands.Helpers do
  @moduledoc "Shared helpers for WebSocket command handlers."

  @doc "Builds a standardized event message map for WebSocket push."
  def event_msg(agent, event_type, title) do
    %{
      type: "event",
      agent: agent,
      event: event_type,
      title: title,
      timestamp: Calendar.strftime(DateTime.utc_now(), "%H:%M:%S")
    }
  end

  @doc "Lists tasks for a company, returning an empty list on error."
  def list_tasks(company) do
    try do
      if company do
        Shazam.TaskBoard.list(%{company: company})
      else
        Shazam.TaskBoard.list()
      end
    catch
      _, _ -> []
    end
  end

  @doc "Returns a tuple `{pending, running, done, awaiting}` of task counts."
  def get_task_counts(company) do
    tasks = list_tasks(company)
    pending = Enum.count(tasks, &(to_string(&1.status) == "pending"))
    running = Enum.count(tasks, &(to_string(&1.status) in ["in_progress", "running"]))
    done = Enum.count(tasks, &(to_string(&1.status) in ["completed", "failed"]))
    awaiting = Enum.count(tasks, &(to_string(&1.status) == "awaiting_approval"))
    {pending, running, done, awaiting}
  end

  @doc "Returns the RalphLoop status for a company: `\"running\"`, `\"paused\"`, or `\"idle\"`."
  def get_ralph_status(company) do
    try do
      if company && Shazam.RalphLoop.exists?(company) do
        case Shazam.RalphLoop.status(company) do
          %{paused: false} -> "running"
          %{paused: true} -> "paused"
          _ -> "idle"
        end
      else
        "idle"
      end
    catch
      _, _ -> "idle"
    end
  end

  @doc "Finds the PM/manager agent name from the agent list. Falls back to `\"pm\"`."
  def find_pm_name(agents) do
    case Enum.find(agents, fn a ->
      role = String.downcase(to_string(a[:role] || ""))
      supervisor = a[:supervisor]
      (String.contains?(role, "manager") or String.contains?(role, "pm")) and supervisor == nil
    end) do
      nil ->
        case Enum.find(agents, fn a ->
          role = String.downcase(to_string(a[:role] || ""))
          String.contains?(role, "manager") or String.contains?(role, "pm")
        end) do
          nil -> "pm"
          agent -> to_string(agent[:name] || "pm")
        end
      agent -> to_string(agent[:name] || "pm")
    end
  end

  @doc "Waits up to `retries * 500ms` for a RalphLoop to appear for the given company."
  def wait_for_ralph(company, retries) when retries > 0 do
    if Shazam.RalphLoop.exists?(company), do: :ok,
    else: (Process.sleep(500); wait_for_ralph(company, retries - 1))
  end
  def wait_for_ralph(_, _), do: :ok

  @doc "Returns the help text shown by the /help command."
  def help_text do
    """
    Commands: /start, /stop, /resume, /restart, /reload, /status, /dashboard, /config, /health
    Tasks: /task <desc>, /tasks, /approve <id>, /aa, /reject <id>, /retry-task <id>, /kill-task <id>
    Agents: /agents, /org
    Plans: /plan <desc>, /plan --list, /plan --show <id>, /plan --approve <id>
    Plugins: /plugins, /plugins reload
    Other: /help, /clear, /quit, /reload
    """
  end
end
