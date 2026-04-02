defmodule Shazam.Doctor do
  @moduledoc "System diagnostics — checks all components and reports health."

  require Logger

  @doc "Run all diagnostic checks. Returns a list of check results."
  def diagnose do
    checks = [
      check_claude_cli(),
      check_daemon(),
      check_workspace(),
      check_port(),
      check_genservers(),
      check_sessions(),
      check_orphaned_processes(),
      check_disk_space(),
      check_task_board(),
      check_company(),
      check_store()
    ]

    %{
      checks: checks,
      passed: Enum.count(checks, &(&1.status == :ok)),
      failed: Enum.count(checks, &(&1.status == :error)),
      warnings: Enum.count(checks, &(&1.status == :warning)),
      total: length(checks),
      timestamp: DateTime.to_iso8601(DateTime.utc_now())
    }
  end

  defp check_claude_cli do
    case System.cmd("which", ["claude"], stderr_to_stdout: true) do
      {path, 0} ->
        # Also check version
        version =
          case System.cmd("claude", ["--version"], stderr_to_stdout: true) do
            {v, 0} -> String.trim(v)
            _ -> "unknown"
          end

        %{name: "Claude CLI", status: :ok, message: "Found at #{String.trim(path)} (#{version})"}

      _ ->
        %{
          name: "Claude CLI",
          status: :error,
          message: "Not found in PATH. Install: npm install -g @anthropic-ai/claude-code"
        }
    end
  rescue
    _ -> %{name: "Claude CLI", status: :error, message: "Failed to check — command execution error"}
  end

  defp check_daemon do
    if Shazam.Daemon.daemon_mode?() do
      pid = :os.getpid() |> to_string()
      port = Shazam.Daemon.port()
      %{name: "Daemon", status: :ok, message: "Running (PID: #{pid}, port: #{port})"}
    else
      %{name: "Daemon", status: :warning, message: "Not in daemon mode (SHAZAM_DAEMON not set)"}
    end
  rescue
    _ -> %{name: "Daemon", status: :warning, message: "Daemon module not available"}
  end

  defp check_workspace do
    workspace = Shazam.Config.global_workspace()

    cond do
      !workspace ->
        %{name: "Workspace", status: :error, message: "No workspace configured"}

      !File.dir?(workspace) ->
        %{name: "Workspace", status: :error, message: "Directory not found: #{workspace}"}

      !File.exists?(Path.join(workspace, ".shazam/shazam.yaml")) &&
          !File.exists?(Path.join(workspace, "shazam.yaml")) ->
        %{name: "Workspace", status: :warning, message: "No shazam.yaml found in #{workspace}"}

      true ->
        %{name: "Workspace", status: :ok, message: workspace}
    end
  end

  defp check_port do
    port = Shazam.Daemon.port()
    %{name: "API Port", status: :ok, message: "Listening on #{port}"}
  rescue
    _ -> %{name: "API Port", status: :warning, message: "Could not determine port"}
  end

  defp check_genservers do
    servers = [
      {Shazam.TaskBoard, "TaskBoard"},
      {Shazam.SessionPool, "SessionPool"},
      {Shazam.Metrics, "Metrics"},
      {Shazam.API.EventBus, "EventBus"},
      {Shazam.CircuitBreaker, "CircuitBreaker"},
      {Shazam.ConfigSync, "ConfigSync"},
      {Shazam.AuditLog, "AuditLog"},
      {Shazam.Webhook, "Webhook"}
    ]

    alive = Enum.filter(servers, fn {mod, _} -> GenServer.whereis(mod) != nil end)
    dead = Enum.reject(servers, fn {mod, _} -> GenServer.whereis(mod) != nil end)

    if length(dead) == 0 do
      %{name: "GenServers", status: :ok, message: "All #{length(alive)} services running"}
    else
      dead_names = Enum.map_join(dead, ", ", fn {_, n} -> n end)

      %{
        name: "GenServers",
        status: :error,
        message: "Down: #{dead_names} (#{length(alive)}/#{length(servers)} running)"
      }
    end
  end

  defp check_sessions do
    try do
      sessions = Shazam.SessionPool.list()
      active = Enum.count(sessions, & &1.alive)
      idle = length(sessions) - active

      %{
        name: "Sessions",
        status: :ok,
        message: "#{length(sessions)} total (#{active} active, #{idle} idle)"
      }
    catch
      _, _ -> %{name: "Sessions", status: :warning, message: "Could not query session pool"}
    end
  end

  defp check_orphaned_processes do
    try do
      {output, 0} =
        System.cmd("pgrep", ["-f", "claude.*stream-json"], stderr_to_stdout: true)

      count = output |> String.split("\n", trim: true) |> length()

      sessions =
        try do
          Shazam.SessionPool.list() |> length()
        catch
          _, _ -> 0
        end

      # -1 for daemon itself
      orphans = max(0, count - sessions - 1)

      if orphans > 0 do
        %{
          name: "Orphaned Processes",
          status: :warning,
          message: "#{orphans} potential orphaned claude processes"
        }
      else
        %{
          name: "Orphaned Processes",
          status: :ok,
          message: "None detected (#{count} total claude processes)"
        }
      end
    catch
      _, _ -> %{name: "Orphaned Processes", status: :ok, message: "No claude processes found"}
    end
  end

  defp check_disk_space do
    store_dir = Shazam.Store.data_dir()

    if File.dir?(store_dir) do
      files = File.ls!(store_dir) |> length()
      %{name: "Store", status: :ok, message: "#{files} files in #{store_dir}"}
    else
      %{name: "Store", status: :warning, message: "Store directory not found"}
    end
  rescue
    _ -> %{name: "Store", status: :warning, message: "Could not check store"}
  end

  defp check_task_board do
    try do
      tasks = Shazam.TaskBoard.list(%{})
      pending = Enum.count(tasks, &(&1.status == :pending))
      running = Enum.count(tasks, &(&1.status == :in_progress))
      failed = Enum.count(tasks, &(&1.status == :failed))

      status =
        cond do
          failed > 10 -> :warning
          true -> :ok
        end

      %{
        name: "TaskBoard",
        status: status,
        message:
          "#{length(tasks)} tasks (#{pending} pending, #{running} running, #{failed} failed)"
      }
    catch
      _, _ -> %{name: "TaskBoard", status: :error, message: "TaskBoard not responding"}
    end
  end

  defp check_company do
    try do
      companies =
        Registry.select(Shazam.CompanyRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])

      if length(companies) > 0 do
        names = Enum.map_join(companies, ", ", &to_string/1)
        %{name: "Companies", status: :ok, message: "#{length(companies)} active: #{names}"}
      else
        %{name: "Companies", status: :warning, message: "No companies running"}
      end
    catch
      _, _ ->
        %{name: "Companies", status: :warning, message: "Could not query company registry"}
    end
  end

  defp check_store do
    try do
      dir = Shazam.Store.data_dir()

      if File.dir?(dir) do
        %{name: "Disk Store", status: :ok, message: dir}
      else
        %{name: "Disk Store", status: :error, message: "Missing: #{dir}"}
      end
    catch
      _, _ -> %{name: "Disk Store", status: :warning, message: "Could not check"}
    end
  end
end
