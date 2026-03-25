defmodule Shazam.SessionPool do
  @moduledoc """
  Maintains a pool of reusable Claude Code sessions, one per agent.
  Sessions are kept alive between tasks to preserve context and save tokens.
  """

  use GenServer
  require Logger

  @idle_timeout :timer.minutes(15)
  @max_tasks_before_reset 8

  # %{agent_name => %{pid: pid, last_used: DateTime, struct_hash: hash, task_count: int}}
  defstruct sessions: %{}

  # Keys that define session identity — if these change, session must be recreated.
  # system_prompt is NOT here because it's only used at creation time.
  # Memory bank changes, skill edits, etc. do NOT force session recreation.
  @structural_keys [:model, :allowed_tools, :cwd, :add_dir, :permission_mode, :timeout]

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets or creates a session for the given agent.
  Returns {:ok, pid, :new} for fresh sessions or {:ok, pid, :reused} for existing ones.
  """
  def checkout(agent_name, session_opts) do
    GenServer.call(__MODULE__, {:checkout, agent_name, session_opts}, :timer.minutes(2))
  end

  @doc "Marks a session as idle (available for reuse). Does NOT kill it."
  def checkin(agent_name) do
    GenServer.cast(__MODULE__, {:checkin, agent_name})
  end

  @doc "Kills a specific agent's session."
  def kill(agent_name) do
    GenServer.call(__MODULE__, {:kill, agent_name}, :timer.seconds(10))
  end

  @doc "Kills all sessions."
  def kill_all do
    GenServer.call(__MODULE__, :kill_all, :timer.seconds(30))
  end

  @doc "Returns info about all active sessions."
  def list do
    GenServer.call(__MODULE__, :list)
  end

  # --- Callbacks ---

  @impl true
  def init(_opts) do
    # Periodically clean up idle sessions
    :timer.send_interval(:timer.minutes(5), :cleanup_idle)
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:checkout, agent_name, session_opts}, _from, state) do
    # Only hash structural keys (model, tools, cwd, modules, permissions).
    # system_prompt is excluded — memory bank changes, skill edits, etc.
    # do NOT force session recreation. This saves thousands of tokens.
    struct_hash = structural_hash(session_opts)

    case Map.get(state.sessions, agent_name) do
      %{pid: pid, struct_hash: ^struct_hash, task_count: count}
          when count >= @max_tasks_before_reset ->
        # Too many tasks accumulated — reset session to avoid context bloat
        Logger.info("[SessionPool] Session for '#{agent_name}' hit #{count} tasks — resetting to save tokens")
        stop_session(pid)
        case create_session(agent_name, session_opts, struct_hash, state) do
          {:ok, pid, new_state} -> {:reply, {:ok, pid, :new}, new_state}
          {:error, reason} -> {:reply, {:error, reason}, %{state | sessions: Map.delete(state.sessions, agent_name)}}
        end

      %{pid: pid, struct_hash: ^struct_hash} = entry ->
        # Same structural config — check if session is still alive
        if Process.alive?(pid) do
          task_count = (entry[:task_count] || 0) + 1
          Logger.info("[SessionPool] Reusing session for '#{agent_name}' (task ##{task_count})")
          updated = %{entry | last_used: DateTime.utc_now(), task_count: task_count, in_use: true}
          {:reply, {:ok, pid, :reused}, %{state | sessions: Map.put(state.sessions, agent_name, updated)}}
        else
          # Session died — create new one
          Logger.info("[SessionPool] Session for '#{agent_name}' died, creating new one")
          case create_session(agent_name, session_opts, struct_hash, state) do
            {:ok, pid, new_state} -> {:reply, {:ok, pid, :new}, new_state}
            {:error, reason} -> {:reply, {:error, reason}, %{state | sessions: Map.delete(state.sessions, agent_name)}}
          end
        end

      %{pid: pid} ->
        # Structural config changed (model, tools, cwd) — must replace session
        Logger.info("[SessionPool] Structural config changed for '#{agent_name}', replacing session")
        stop_session(pid)
        case create_session(agent_name, session_opts, struct_hash, state) do
          {:ok, pid, new_state} -> {:reply, {:ok, pid, :new}, new_state}
          {:error, reason} -> {:reply, {:error, reason}, %{state | sessions: Map.delete(state.sessions, agent_name)}}
        end

      nil ->
        # No session — create one
        case create_session(agent_name, session_opts, struct_hash, state) do
          {:ok, pid, new_state} -> {:reply, {:ok, pid, :new}, new_state}
          {:error, reason} -> {:reply, {:error, reason}, state}
        end
    end
  end

  def handle_call({:kill, agent_name}, _from, state) do
    case Map.pop(state.sessions, agent_name) do
      {nil, _} ->
        {:reply, :ok, state}

      {%{pid: pid}, sessions} ->
        stop_session(pid)
        Logger.info("[SessionPool] Killed session for '#{agent_name}'")
        {:reply, :ok, %{state | sessions: sessions}}
    end
  end

  def handle_call(:kill_all, _from, state) do
    count = map_size(state.sessions)
    Enum.each(state.sessions, fn {name, %{pid: pid}} ->
      stop_session(pid)
      Logger.info("[SessionPool] Killed session for '#{name}'")
    end)

    {:reply, {:ok, count}, %{state | sessions: %{}}}
  end

  def handle_call(:list, _from, state) do
    info =
      state.sessions
      |> Enum.map(fn {name, entry} ->
        %{
          agent: name,
          alive: Process.alive?(entry.pid),
          last_used: entry.last_used,
          task_count: entry.task_count
        }
      end)

    {:reply, info, state}
  end

  @impl true
  def handle_cast({:checkin, agent_name}, state) do
    case Map.get(state.sessions, agent_name) do
      nil -> {:noreply, state}
      entry ->
        updated = %{entry | last_used: DateTime.utc_now(), in_use: false}
        {:noreply, %{state | sessions: Map.put(state.sessions, agent_name, updated)}}
    end
  end

  @impl true
  def handle_info(:cleanup_idle, state) do
    now = DateTime.utc_now()

    {to_kill, to_keep} =
      state.sessions
      |> Enum.split_with(fn {_name, entry} ->
        not Map.get(entry, :in_use, false) and
          (DateTime.diff(now, entry.last_used, :millisecond) > @idle_timeout or
           not Process.alive?(entry.pid))
      end)

    Enum.each(to_kill, fn {name, %{pid: pid}} ->
      if Process.alive?(pid), do: stop_session(pid)
      Logger.info("[SessionPool] Cleaned up idle session for '#{name}'")
    end)

    # Reap orphaned OS claude processes not tracked by the pool
    reap_orphaned_processes(Map.new(to_keep))

    {:noreply, %{state | sessions: Map.new(to_keep)}}
  end

  # --- Helpers ---

  defp create_session(agent_name, session_opts, struct_hash, state) do
    child_spec = %{
      id: make_ref(),
      start: {ClaudeCode, :start_link, [session_opts]},
      restart: :temporary
    }

    case DynamicSupervisor.start_child(Shazam.AgentSupervisor, child_spec) do
      {:ok, pid} ->
        Logger.info("[SessionPool] Created new session for '#{agent_name}'")
        entry = %{pid: pid, struct_hash: struct_hash, last_used: DateTime.utc_now(), task_count: 1, in_use: true}
        {:ok, pid, %{state | sessions: Map.put(state.sessions, agent_name, entry)}}

      {:error, reason} ->
        Logger.error("[SessionPool] Failed to create session for '#{agent_name}': #{inspect(reason)}")
        {:error, {:session_start_failed, reason}}
    end
  end

  defp structural_hash(session_opts) do
    session_opts
    |> Keyword.take(@structural_keys)
    |> :erlang.phash2()
  end

  defp stop_session(pid) do
    try do
      ClaudeCode.stop(pid)
    rescue
      _ -> :ok
    catch
      :exit, _ -> :ok
    end
  end

  # Kill orphaned OS-level claude processes that are NOT tracked by any active session.
  # This handles the case where ClaudeCode.start_link fails mid-way, leaving a CLI process alive.
  defp reap_orphaned_processes(active_sessions) do
    daemon_pid = to_string(:os.getpid())

    # Get all OS pids of claude --output-format stream-json processes
    os_claude_pids = try do
      {output, 0} = System.cmd("pgrep", ["-f", "claude.*stream-json"], stderr_to_stdout: true)
      output
      |> String.split("\n", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
    catch
      _, _ -> []
    end

    if length(os_claude_pids) <= map_size(active_sessions) do
      # No orphans — count matches or is less
      :ok
    else
      # Get the OS PIDs of active sessions' child processes
      tracked_erlang_pids = Enum.map(active_sessions, fn {_name, entry} -> entry.pid end)

      tracked_os_pids = Enum.flat_map(tracked_erlang_pids, fn erlang_pid ->
        try do
          # Get the OS PID from the Erlang port linked to this process
          info = Process.info(erlang_pid, [:links])
          links = (info || [])[:links] || []
          Enum.flat_map(links, fn
            link when is_port(link) ->
              case Port.info(link, :os_pid) do
                {:os_pid, os_pid} -> [to_string(os_pid)]
                _ -> []
              end
            _ -> []
          end)
        catch
          _, _ -> []
        end
      end)

      # Find orphans: OS claude processes not tracked
      orphans = os_claude_pids -- tracked_os_pids -- [daemon_pid]

      # Only kill processes that are clearly orphaned (not our current process)
      excess = length(orphans) - map_size(active_sessions)
      if excess > 0 do
        Logger.warning("[SessionPool] Found #{length(orphans)} potential orphaned claude processes, killing #{excess}")
        orphans
        |> Enum.take(excess)
        |> Enum.each(fn pid_str ->
          try do
            System.cmd("kill", [pid_str])
            Logger.info("[SessionPool] Reaped orphaned claude process: #{pid_str}")
          catch
            _, _ -> :ok
          end
        end)
      end
    end
  rescue
    _ -> :ok
  end
end
