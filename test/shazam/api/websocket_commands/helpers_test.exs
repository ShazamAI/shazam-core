defmodule Shazam.API.WebSocketCommands.HelpersTest do
  use ExUnit.Case, async: true

  alias Shazam.API.WebSocketCommands.Helpers

  describe "event_msg/3" do
    test "builds a correctly shaped event message" do
      msg = Helpers.event_msg("agent1", "task_created", "Build auth")

      assert msg.type == "event"
      assert msg.agent == "agent1"
      assert msg.event == "task_created"
      assert msg.title == "Build auth"
      assert is_binary(msg.timestamp)
    end

    test "timestamp is in HH:MM:SS format" do
      msg = Helpers.event_msg("sys", "info", "hello")
      assert msg.timestamp =~ ~r/\d{2}:\d{2}:\d{2}/
    end

    test "handles system agent" do
      msg = Helpers.event_msg("system", "error", "Something failed")
      assert msg.agent == "system"
      assert msg.event == "error"
    end
  end

  describe "find_pm_name/1" do
    test "finds agent with 'Project Manager' role and no supervisor" do
      agents = [
        %{name: "pm", role: "Project Manager", supervisor: nil},
        %{name: "dev1", role: "Senior Developer", supervisor: "pm"}
      ]

      assert Helpers.find_pm_name(agents) == "pm"
    end

    test "finds agent with 'PM' in role" do
      agents = [
        %{name: "ralph", role: "PM Lead", supervisor: nil},
        %{name: "dev1", role: "Developer", supervisor: "ralph"}
      ]

      assert Helpers.find_pm_name(agents) == "ralph"
    end

    test "falls back to manager with supervisor if no top-level manager" do
      agents = [
        %{name: "cto", role: "CTO", supervisor: nil},
        %{name: "manager", role: "Engineering Manager", supervisor: "cto"}
      ]

      assert Helpers.find_pm_name(agents) == "manager"
    end

    test "returns 'pm' when no agent matches" do
      agents = [
        %{name: "dev1", role: "Developer", supervisor: nil},
        %{name: "dev2", role: "Developer", supervisor: nil}
      ]

      assert Helpers.find_pm_name(agents) == "pm"
    end

    test "returns 'pm' for empty list" do
      assert Helpers.find_pm_name([]) == "pm"
    end

    test "handles keyword list agents" do
      agents = [
        [name: "boss", role: "Project Manager", supervisor: nil],
        [name: "dev", role: "Developer", supervisor: "boss"]
      ]

      assert Helpers.find_pm_name(agents) == "boss"
    end
  end

  describe "get_task_counts/1" do
    test "returns four-element tuple of zeroes when no tasks" do
      # Use a non-existent company to get zero counts
      {pending, running, done, awaiting} =
        Helpers.get_task_counts("nonexistent_#{System.unique_integer([:positive])}")

      assert is_integer(pending)
      assert is_integer(running)
      assert is_integer(done)
      assert is_integer(awaiting)
    end
  end

  describe "get_ralph_status/1" do
    test "returns 'idle' when no company" do
      assert Helpers.get_ralph_status(nil) == "idle"
    end

    test "returns 'idle' for non-existent company" do
      assert Helpers.get_ralph_status("no_such_company_#{System.unique_integer([:positive])}") == "idle"
    end
  end

  describe "help_text/0" do
    test "contains expected command sections" do
      text = Helpers.help_text()
      assert text =~ "/start"
      assert text =~ "/stop"
      assert text =~ "/tasks"
      assert text =~ "/help"
      assert text =~ "/plan"
    end
  end

  describe "wait_for_ralph/2" do
    test "returns :ok immediately when retries exhausted" do
      assert Helpers.wait_for_ralph("nonexistent", 0) == :ok
    end
  end
end
