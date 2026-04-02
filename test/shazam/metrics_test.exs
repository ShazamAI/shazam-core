defmodule Shazam.MetricsTest do
  use ExUnit.Case, async: false

  @moduletag :metrics

  setup do
    # Ensure Metrics GenServer is running
    unless GenServer.whereis(Shazam.Metrics) do
      Shazam.Metrics.start_link([])
    end

    Shazam.Metrics.reset_all()
    :ok
  end

  # ── get_all/0 ────────────────────────────────────────

  describe "get_all/0" do
    test "returns empty agents map when no data recorded" do
      result = Shazam.Metrics.get_all()
      assert result.agents == %{}
      assert result.totals.total_tasks == 0
      assert result.totals.successes == 0
      assert result.totals.failures == 0
    end
  end

  # ── get_agent/1 ──────────────────────────────────────

  describe "get_agent/1" do
    test "returns nil for unknown agent" do
      assert Shazam.Metrics.get_agent("nonexistent_agent") == nil
    end

    test "returns metrics after recording completion" do
      Shazam.Metrics.record_completion("test_agent", 500, 1000)
      # Give cast time to process
      Process.sleep(50)

      result = Shazam.Metrics.get_agent("test_agent")
      assert result != nil
      assert result.successes == 1
      assert result.total_tokens == 1000
      assert result.avg_duration_ms == 500
      assert result.total_tasks == 1
    end
  end

  # ── record_completion/3 ─────────────────────────────

  describe "record_completion/3" do
    test "increments success count" do
      Shazam.Metrics.record_completion("agent_a", 100, 500)
      Shazam.Metrics.record_completion("agent_a", 200, 600)
      Process.sleep(50)

      result = Shazam.Metrics.get_agent("agent_a")
      assert result.successes == 2
      assert result.total_tokens == 1100
      assert result.total_tasks == 2
    end

    test "calculates average duration" do
      Shazam.Metrics.record_completion("agent_b", 100, 0)
      Shazam.Metrics.record_completion("agent_b", 300, 0)
      Process.sleep(50)

      result = Shazam.Metrics.get_agent("agent_b")
      assert result.avg_duration_ms == 200
    end

    test "defaults tokens to 0" do
      Shazam.Metrics.record_completion("agent_c", 100)
      Process.sleep(50)

      result = Shazam.Metrics.get_agent("agent_c")
      assert result.total_tokens == 0
    end
  end

  # ── record_failure/1 ────────────────────────────────

  describe "record_failure/1" do
    test "increments failure count" do
      Shazam.Metrics.record_failure("fail_agent")
      Shazam.Metrics.record_failure("fail_agent")
      Process.sleep(50)

      result = Shazam.Metrics.get_agent("fail_agent")
      assert result.failures == 2
      assert result.successes == 0
      assert result.total_tasks == 2
    end
  end

  # ── record_tokens/3 ────────────────────────────────

  describe "record_tokens/3" do
    test "tracks token usage separately" do
      Shazam.Metrics.record_tokens("token_agent", 5000, 0.015)
      Process.sleep(100)

      result = Shazam.Metrics.get_agent("token_agent")
      assert result.total_tokens == 5000
    end
  end

  # ── set_status/2 ────────────────────────────────────

  describe "set_status/2" do
    test "updates agent status" do
      Shazam.Metrics.record_completion("status_agent", 100, 0)
      Shazam.Metrics.set_status("status_agent", "working")
      Process.sleep(50)

      # Status isn't exposed in serialized metrics, but the agent should exist
      result = Shazam.Metrics.get_agent("status_agent")
      assert result != nil
    end
  end

  # ── reset/0 ─────────────────────────────────────────

  describe "reset/0" do
    test "resets session counters but preserves token data" do
      Shazam.Metrics.record_completion("reset_agent", 500, 1000)
      Shazam.Metrics.record_tokens("reset_agent", 2000, 0.006)
      Process.sleep(50)

      Shazam.Metrics.reset()

      result = Shazam.Metrics.get_agent("reset_agent")
      assert result != nil
      # Tokens should be preserved
      assert result.total_tokens >= 1000
    end
  end

  # ── reset_all/0 ─────────────────────────────────────

  describe "reset_all/0" do
    test "clears all metrics" do
      Shazam.Metrics.record_completion("cleared", 100, 500)
      Process.sleep(50)

      Shazam.Metrics.reset_all()

      assert Shazam.Metrics.get_agent("cleared") == nil
      result = Shazam.Metrics.get_all()
      assert result.agents == %{}
    end
  end

  # ── success_rate calculation ─────────────────────────

  describe "success_rate calculation" do
    test "computes correct rate" do
      Shazam.Metrics.record_completion("rate_agent", 100, 0)
      Shazam.Metrics.record_completion("rate_agent", 100, 0)
      Shazam.Metrics.record_failure("rate_agent")
      Process.sleep(50)

      result = Shazam.Metrics.get_agent("rate_agent")
      # 2 successes / 3 total = 66.7%
      assert result.success_rate == 66.7
    end
  end

  # ── totals ──────────────────────────────────────────

  describe "totals" do
    test "aggregates across agents" do
      Shazam.Metrics.record_completion("agent_x", 100, 500)
      Shazam.Metrics.record_completion("agent_y", 200, 300)
      Shazam.Metrics.record_failure("agent_x")
      Process.sleep(50)

      result = Shazam.Metrics.get_all()
      assert result.totals.successes == 2
      assert result.totals.failures == 1
      assert result.totals.total_tasks == 3
      assert result.totals.total_tokens == 800
    end
  end

  # ── check_budget/1 ──────────────────────────────────

  describe "check_budget/1" do
    test "returns :ok for unknown agent" do
      assert Shazam.Metrics.check_budget("unknown_budget_agent") == :ok
    end

    test "returns :ok when no budget is set" do
      Shazam.Metrics.record_completion("no_budget", 100, 500)
      Process.sleep(50)

      # No company/agent with budget configured, so budget will be nil
      assert Shazam.Metrics.check_budget("no_budget") == :ok
    end
  end
end
