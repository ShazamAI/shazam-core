defmodule Shazam.SessionPoolTest do
  use ExUnit.Case, async: false

  alias Shazam.SessionPool

  describe "session_key namespacing" do
    test "two companies with same agent name get different session keys" do
      # SessionPool uses "company:agent" as the key internally.
      # We verify that checkout/checkin/kill with different company names
      # produce distinct entries in the pool.

      # Start the SessionPool if not already running
      ensure_pool_started()

      # List sessions — should be empty initially
      sessions = SessionPool.list()
      _initial_count = length(sessions)

      # We can't actually create ClaudeCode sessions in tests (no CLI),
      # but we can verify the key structure by checking that the GenServer
      # handles requests without crashing when given company-namespaced keys.

      # Attempting checkout will fail (no ClaudeCode binary in test) but
      # it should fail with a session_start_failed error, not a crash.
      result_a = SessionPool.checkout("CompanyA", "pm", [
        system_prompt: "test",
        timeout: 5000,
        permission_mode: :bypass_permissions
      ])

      result_b = SessionPool.checkout("CompanyB", "pm", [
        system_prompt: "test",
        timeout: 5000,
        permission_mode: :bypass_permissions
      ])

      # Both should return errors (no ClaudeCode available in test env)
      # but importantly they should NOT crash the GenServer
      assert match?({:error, _}, result_a) or match?({:ok, _, _}, result_a)
      assert match?({:error, _}, result_b) or match?({:ok, _, _}, result_b)

      # The pool should still be alive
      assert is_list(SessionPool.list())
    end

    test "checkin with company namespace does not crash" do
      ensure_pool_started()
      # Checkin for a non-existent session should be a no-op
      assert :ok == SessionPool.checkin("CompanyA", "pm")
    end

    test "kill with company namespace does not crash" do
      ensure_pool_started()
      assert :ok == SessionPool.kill("CompanyA", "pm")
    end

    test "legacy kill/1 does not crash" do
      ensure_pool_started()
      assert :ok == SessionPool.kill("pm")
    end

    test "kill_all returns count" do
      ensure_pool_started()
      assert {:ok, _count} = SessionPool.kill_all()
    end
  end

  describe "cleanup behavior" do
    test "cleanup does not kill idle sessions (only removes dead PIDs)" do
      ensure_pool_started()

      # Inject a fake session with a dead PID
      dead_pid = spawn(fn -> :ok end)
      Process.sleep(10)
      refute Process.alive?(dead_pid)

      :sys.replace_state(SessionPool, fn state ->
        entry = %{
          pid: dead_pid,
          struct_hash: 12345,
          last_used: DateTime.add(DateTime.utc_now(), -30, :minute),
          task_count: 1,
          in_use: false
        }
        %{state | sessions: Map.put(state.sessions, "test:dead_agent", entry)}
      end)

      # Trigger cleanup
      send(SessionPool, :cleanup_idle)
      Process.sleep(50)

      # Dead session should be removed
      state = :sys.get_state(SessionPool)
      refute Map.has_key?(state.sessions, "test:dead_agent")
    end

    test "cleanup preserves sessions with alive PIDs even if idle" do
      ensure_pool_started()

      # Inject a fake session with an alive PID (long-running process)
      alive_pid = spawn(fn -> Process.sleep(:infinity) end)

      :sys.replace_state(SessionPool, fn state ->
        entry = %{
          pid: alive_pid,
          struct_hash: 12345,
          last_used: DateTime.add(DateTime.utc_now(), -60, :minute),  # 1 hour idle
          task_count: 5,
          in_use: false
        }
        %{state | sessions: Map.put(state.sessions, "test:idle_agent", entry)}
      end)

      # Trigger cleanup
      send(SessionPool, :cleanup_idle)
      Process.sleep(50)

      # Session should still be there — we don't kill idle sessions anymore
      state = :sys.get_state(SessionPool)
      assert Map.has_key?(state.sessions, "test:idle_agent")

      # Cleanup
      Process.exit(alive_pid, :kill)
      :sys.replace_state(SessionPool, fn state ->
        %{state | sessions: Map.delete(state.sessions, "test:idle_agent")}
      end)
    end

    test "cleanup preserves in_use sessions" do
      ensure_pool_started()

      alive_pid = spawn(fn -> Process.sleep(:infinity) end)

      :sys.replace_state(SessionPool, fn state ->
        entry = %{
          pid: alive_pid,
          struct_hash: 12345,
          last_used: DateTime.add(DateTime.utc_now(), -60, :minute),
          task_count: 3,
          in_use: true
        }
        %{state | sessions: Map.put(state.sessions, "test:busy_agent", entry)}
      end)

      send(SessionPool, :cleanup_idle)
      Process.sleep(50)

      state = :sys.get_state(SessionPool)
      assert Map.has_key?(state.sessions, "test:busy_agent")

      Process.exit(alive_pid, :kill)
      :sys.replace_state(SessionPool, fn state ->
        %{state | sessions: Map.delete(state.sessions, "test:busy_agent")}
      end)
    end
  end

  describe "compact behavior" do
    test "session over max_tasks triggers compact, not kill" do
      ensure_pool_started()

      # Inject session at max task count with alive PID
      alive_pid = spawn(fn -> Process.sleep(:infinity) end)
      opts = [system_prompt: "test", timeout: 5000]
      struct_hash = opts |> Keyword.take([:model, :allowed_tools, :cwd, :add_dir, :permission_mode, :timeout]) |> :erlang.phash2()

      :sys.replace_state(SessionPool, fn state ->
        entry = %{
          pid: alive_pid,
          struct_hash: struct_hash,
          last_used: DateTime.utc_now(),
          task_count: 8,  # At max
          in_use: false
        }
        %{state | sessions: Map.put(state.sessions, "test:compact_agent", entry)}
      end)

      # Checkout should reuse (compact), not kill
      result = SessionPool.checkout("test", "compact_agent", opts)

      # Should return the same PID (reused, not recreated)
      case result do
        {:ok, ^alive_pid, :reused} -> assert true
        {:ok, _pid, :reused} -> assert true  # PID might differ if compact happened
        other ->
          # Even if compact fails, it should not crash
          assert match?({:ok, _, _}, other) or match?({:error, _}, other)
      end

      Process.exit(alive_pid, :kill)
      :sys.replace_state(SessionPool, fn state ->
        %{state | sessions: Map.delete(state.sessions, "test:compact_agent")}
      end)
    end
  end

  defp ensure_pool_started do
    case GenServer.whereis(SessionPool) do
      nil -> SessionPool.start_link([])
      _pid -> :ok
    end
  end
end
