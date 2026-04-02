defmodule Shazam.ConfigTest do
  use ExUnit.Case, async: true

  alias Shazam.Config

  # ── workspace ────────────────────────────────────────

  describe "workspace/0" do
    test "returns global workspace as a binary" do
      assert is_binary(Config.workspace())
    end
  end

  describe "workspace/1" do
    test "with nil returns global workspace" do
      assert Config.workspace(nil) == Config.workspace()
    end

    test "with agent profile without workspace key falls back to global" do
      profile = %{name: "dev1"}
      assert Config.workspace(profile) == Config.global_workspace()
    end

    test "with agent profile with nil workspace falls back to global" do
      profile = %{workspace: nil}
      assert Config.workspace(profile) == Config.global_workspace()
    end

    test "with agent profile referencing unknown workspace falls back to global" do
      profile = %{workspace: "nonexistent_ws"}
      assert Config.workspace(profile) == Config.global_workspace()
    end
  end

  # ── global_workspace ─────────────────────────────────

  describe "global_workspace/0" do
    test "returns a binary path" do
      assert is_binary(Config.global_workspace())
    end
  end

  # ── normalize_budget ─────────────────────────────────

  describe "normalize_budget/1" do
    test "nil returns nil (unlimited)" do
      assert Config.normalize_budget(nil) == nil
    end

    test "0 returns nil (unlimited)" do
      assert Config.normalize_budget(0) == nil
    end

    test "positive integer returns value" do
      assert Config.normalize_budget(100_000) == 100_000
    end

    test "1 returns 1" do
      assert Config.normalize_budget(1) == 1
    end

    test "negative integer returns nil" do
      assert Config.normalize_budget(-100) == nil
    end

    test "float returns nil" do
      assert Config.normalize_budget(3.14) == nil
    end

    test "string returns nil" do
      assert Config.normalize_budget("50000") == nil
    end

    test "atom returns nil" do
      assert Config.normalize_budget(:infinite) == nil
    end
  end

  # ── unlimited_budget? ───────────────────────────────

  describe "unlimited_budget?/1" do
    test "nil is unlimited" do
      assert Config.unlimited_budget?(nil)
    end

    test "0 is unlimited" do
      assert Config.unlimited_budget?(0)
    end

    test "positive integer is not unlimited" do
      refute Config.unlimited_budget?(100_000)
    end

    test "1 is not unlimited" do
      refute Config.unlimited_budget?(1)
    end

    test "negative is not unlimited" do
      refute Config.unlimited_budget?(-1)
    end

    test "string is not unlimited" do
      refute Config.unlimited_budget?("0")
    end
  end

  # ── poll_interval ────────────────────────────────────

  describe "poll_interval/0" do
    test "returns an integer" do
      assert is_integer(Config.poll_interval())
    end

    test "returns a positive value" do
      assert Config.poll_interval() > 0
    end

    test "default is 5000" do
      # Default unless overridden in test config
      assert Config.poll_interval() == 5_000
    end
  end

  # ── max_concurrent ───────────────────────────────────

  describe "max_concurrent/0" do
    test "returns an integer" do
      assert is_integer(Config.max_concurrent())
    end

    test "returns a positive value" do
      assert Config.max_concurrent() > 0
    end

    test "default is 4" do
      assert Config.max_concurrent() == 4
    end
  end
end
