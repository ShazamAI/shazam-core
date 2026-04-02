defmodule Shazam.SessionPool do
  @moduledoc """
  Maintains a pool of reusable Claude Code sessions, one per agent.
  Sessions are kept alive between tasks to preserve context and save tokens.
  """

  use GenServer
  require Logger

  @max_tasks_before_compact 8

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

  Sessions are namespaced by company_name to prevent collisions when multiple
  companies have agents with the same name.
  """
  def checkout(company_name, agent_name, session_opts) do
    key = session_key(company_name, agent_name)
    GenServer.call(__MODULE__, {:checkout, key, session_opts}, :timer.minutes(2))
  end

  @doc "Marks a session as idle (available for reuse). Does NOT kill it."
  def checkin(company_name, agent_name) do
    key = session_key(company_name, agent_name)
    GenServer.cast(__MODULE__, {:checkin, key})
  end

  @doc "Kills a specific agent's session."
  def kill(company_name, agent_name) do
    key = session_key(company_name, agent_name)
    GenServer.call(__MODULE__, {:kill, key}, :timer.seconds(10))
  end

  # Legacy arity-1 kill for API routes that don't have company context
  def kill(agent_name) do
    # Find and kill any session matching this agent name (any company)
    GenServer.call(__MODULE__, {:kill_by_agent, agent_name}, :timer.seconds(10))
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
      %{pid: pid, struct_hash: ^struct_hash, task_count: count} = entry
          when count >= @max_tasks_before_compact ->
        # Too many tasks accumulated — compact context instead of destroying session
        if Process.alive?(pid) do
          Logger.info("[SessionPool] Session for '#{agent_name}' hit #{count} tasks — compacting context")
          compact_session(pid)
          task_count = count + 1
          updated = %{entry | last_used: DateTime.utc_now(), task_count: task_count, in_use: true}
          {:reply, {:ok, pid, :reused}, %{state | sessions: Map.put(state.sessions, agent_name, updated)}}
        else
          # Session died — create new one
          Logger.info("[SessionPool] Session for '#{agent_name}' died after #{count} tasks, creating new one")
          case create_session(agent_name, session_opts, struct_hash, state) do
            {:ok, pid, new_state} -> {:reply, {:ok, pid, :new}, new_state}
            {:error, reason} -> {:reply, {:error, reason}, %{state | sessions: Map.delete(state.sessions, agent_name)}}
          end
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

  # Kill all sessions matching a given agent_name (any company prefix)
  def handle_call({:kill_by_agent, agent_name}, _from, state) do
    {to_kill, to_keep} =
      state.sessions
      |> Enum.split_with(fn {key, _entry} ->
        String.ends_with?(key, ":#{agent_name}") or key == agent_name
      end)

    Enum.each(to_kill, fn {_key, %{pid: pid}} -> stop_session(pid) end)

    if to_kill != [] do
      Logger.info("[SessionPool] Killed #{length(to_kill)} session(s) for agent '#{agent_name}'")
    end

    {:reply, :ok, %{state | sessions: Map.new(to_keep)}}
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
    # Only clean up sessions with dead PIDs (process crashed).
    # We do NOT kill idle sessions — they should stay alive while the daemon runs.
    # This preserves context and avoids re-creating sessions (token cost).
    {dead, alive} =
      state.sessions
      |> Enum.split_with(fn {_name, entry} ->
        not Process.alive?(entry.pid)
      end)

    if length(dead) > 0 do
      Enum.each(dead, fn {name, _entry} ->
        Logger.info("[SessionPool] Removed dead session for '#{name}'")
      end)
    end

    to_keep = alive

    # Reap orphaned OS claude processes not tracked by the pool
    reap_orphaned_processes(Map.new(to_keep))

    {:noreply, %{state | sessions: Map.new(to_keep)}}
  end

  # --- Helpers ---

  defp session_key(company_name, agent_name) do
    "#{company_name}:#{agent_name}"
  end

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

  # Send /compact to Claude CLI to shrink context without killing the session.
  # This summarizes conversation history, keeping the system prompt intact.
  defp compact_session(pid) do
    Task.start(fn ->
      try do
        # Stream /compact command — it runs asynchronously in the Claude session
        ClaudeCode.stream(pid, "/compact")
        |> Stream.run()
        Logger.info("[SessionPool] Compacted session #{inspect(pid)}")
      rescue
        e ->
          Logger.warning("[SessionPool] Failed to compact session #{inspect(pid)}: #{Exception.message(e)}")
      catch
        :exit, reason ->
          Logger.warning("[SessionPool] Session #{inspect(pid)} exited during compact: #{inspect(reason)}")
      end
    end)
  end

  defp stop_session(pid) do
    try do
      ClaudeCode.stop(pid)
    rescue
      e ->
        Logger.debug("[SessionPool] Error stopping session #{inspect(pid)}: #{Exception.message(e)}")
        :ok
    catch
      :exit, reason ->
        Logger.debug("[SessionPool] Session #{inspect(pid)} already exited: #{inspect(reason)}")
        :ok
    end
  end

  # Kill orphaned OS-level claude processes that are NOT tracked by any active session.
  # This handles the case where ClaudeCode.start_link fails mid-way, leaving a CLI process alive.
  #
  # SAFETY: Only kills processes that are:
  # 1. Not tracked by any session (tracked via Erlang port → OS PID mapping)
  # 2. Not the daemon process itself
  # 3. Older than 2 minutes (grace period for sessions being created)
  # 4. Not a child of any tracked process (avoids killing subprocesses)
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

    # Don't bother if count matches what we expect
    # Each session can have 1-3 OS processes (node + children)
    expected_max = map_size(active_sessions) * 3 + 1  # +1 for daemon
    if length(os_claude_pids) <= expected_max do
      :ok
    else
      # Get ALL OS PIDs associated with tracked sessions
      tracked_os_pids = collect_tracked_os_pids(active_sessions)

      # Find truly orphaned processes (not tracked, not daemon)
      orphans = os_claude_pids -- tracked_os_pids -- [daemon_pid]

      # Additional safety: check process age (only kill if > 2 minutes old)
      old_orphans = Enum.filter(orphans, fn pid_str ->
        process_age_seconds(pid_str) > 120
      end)

      if length(old_orphans) > 0 do
        Logger.warning("[SessionPool] Found #{length(old_orphans)} orphaned claude processes (#{length(orphans)} total untracked, #{length(old_orphans)} old enough to reap)")
        Enum.each(old_orphans, fn pid_str ->
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

  # Collect ALL OS PIDs from tracked sessions, including child processes
  defp collect_tracked_os_pids(active_sessions) do
    active_sessions
    |> Enum.flat_map(fn {_name, entry} ->
      try do
        erlang_pid = entry.pid
        if Process.alive?(erlang_pid) do
          info = Process.info(erlang_pid, [:links])
          links = (info || [])[:links] || []

          # Get direct port OS PIDs
          port_pids = Enum.flat_map(links, fn
            link when is_port(link) ->
              case Port.info(link, :os_pid) do
                {:os_pid, os_pid} ->
                  parent = to_string(os_pid)
                  # Also get child processes of this PID
                  children = get_child_pids(parent)
                  [parent | children]
                _ -> []
              end
            _ -> []
          end)

          port_pids
        else
          []
        end
      catch
        _, _ -> []
      end
    end)
  end

  # Get child PIDs of a process (node spawns subprocesses)
  defp get_child_pids(parent_pid) do
    try do
      {output, 0} = System.cmd("pgrep", ["-P", parent_pid], stderr_to_stdout: true)
      output |> String.split("\n", trim: true) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    catch
      _, _ -> []
    end
  end

  # Check how old a process is (in seconds). Returns 0 if can't determine.
  defp process_age_seconds(pid_str) do
    try do
      {output, 0} = System.cmd("ps", ["-o", "etime=", "-p", pid_str], stderr_to_stdout: true)
      parse_etime(String.trim(output))
    catch
      _, _ -> 0
    end
  end

  # Parse ps etime format: "MM:SS", "HH:MM:SS", or "D-HH:MM:SS"
  defp parse_etime(etime) do
    parts = String.split(etime, ":")
    case parts do
      [s] -> String.to_integer(s)
      [m, s] -> String.to_integer(m) * 60 + String.to_integer(s)
      [h, m, s] ->
        h = case String.split(h, "-") do
          [d, hh] -> String.to_integer(d) * 24 + String.to_integer(hh)
          [hh] -> String.to_integer(hh)
        end
        h * 3600 + String.to_integer(m) * 60 + String.to_integer(s)
      _ -> 0
    end
  rescue
    e ->
      Logger.debug("[SessionPool] Orphan reaping failed: #{Exception.message(e)}")
      :ok
  end
end
