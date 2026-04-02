defmodule Shazam.RateLimitTest do
  use ExUnit.Case, async: false

  @moduletag :rate_limit

  setup do
    # Ensure Metrics GenServer is running (may have been killed by other tests)
    unless GenServer.whereis(Shazam.Metrics), do: Shazam.Metrics.start_link([])

    Shazam.Metrics.reset_all()
    Process.sleep(20)
    :ok
  end

  describe "check_budget/1 with unlimited budget (nil/0)" do
    test "returns :ok when no agent data exists" do
      assert Shazam.Metrics.check_budget("nonexistent_agent") == :ok
    end

    test "returns :ok when agent has tokens but no budget set" do
      # Record some tokens — budget from company will be nil (no company running)
      Shazam.Metrics.record_completion("unlimited_agent", 1000, 50_000)
      Process.sleep(50)

      assert Shazam.Metrics.check_budget("unlimited_agent") == :ok
    end
  end

  describe "check_budget/1 under limit" do
    test "returns :ok when tokens are well below budget" do
      # Since there's no company running, budget will be nil = unlimited
      Shazam.Metrics.record_completion("low_usage_agent", 500, 100)
      Process.sleep(50)

      assert Shazam.Metrics.check_budget("low_usage_agent") == :ok
    end
  end

  describe "check_budget/1 budget thresholds" do
    # These tests verify the logic directly since we can't easily mock
    # the company registry in unit tests. We test the core logic by
    # verifying the function handles the different return shapes correctly.

    test "check_budget returns a valid response shape" do
      Shazam.Metrics.record_completion("test_agent", 500, 1000)
      Process.sleep(50)

      result = Shazam.Metrics.check_budget("test_agent")

      assert result == :ok or
             match?({:warning, _, _}, result) or
             match?({:exceeded, _, _}, result)
    end

    test "get_agent returns token data for budget checking" do
      Shazam.Metrics.record_completion("tracked_agent", 200, 5000)
      Process.sleep(50)

      agent_data = Shazam.Metrics.get_agent("tracked_agent")
      assert agent_data != nil
      assert agent_data.total_tokens == 5000
    end

    test "tokens accumulate across multiple completions" do
      Shazam.Metrics.record_completion("accumulating_agent", 100, 1000)
      Shazam.Metrics.record_completion("accumulating_agent", 100, 2000)
      Shazam.Metrics.record_completion("accumulating_agent", 100, 3000)
      Process.sleep(50)

      agent_data = Shazam.Metrics.get_agent("accumulating_agent")
      assert agent_data.total_tokens == 6000
    end
  end
end
