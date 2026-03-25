defmodule Shazam.API.WebSocketCommandsTest do
  use ExUnit.Case, async: false

  alias Shazam.API.WebSocketCommands

  @moduletag :websocket_commands

  setup do
    # Clean up tasks before each test
    Shazam.TaskBoard.clear_all()

    conn_state = %{
      company: "test_co",
      workspace: System.tmp_dir!(),
      agents: [
        %{name: "pm", role: "Project Manager", supervisor: nil},
        %{name: "dev1", role: "Senior Developer", supervisor: "pm"}
      ],
      config: %{mission: "Test mission"}
    }

    %{conn_state: conn_state}
  end

  describe "handle/2 - /help" do
    test "returns help text", %{conn_state: conn_state} do
      result = WebSocketCommands.handle("/help", conn_state)
      assert [msg] = result
      assert msg.type == "event"
      assert msg.event == "info"
      assert msg.title =~ "Commands:"
    end
  end

  describe "handle/2 - /tasks" do
    test "returns a task_list message", %{conn_state: conn_state} do
      result = WebSocketCommands.handle("/tasks", conn_state)
      assert [msg] = result
      assert msg.type == "task_list"
      assert is_list(msg.tasks)
    end
  end

  describe "handle/2 - /task" do
    test "creates a task and returns confirmation", %{conn_state: conn_state} do
      result = WebSocketCommands.handle("/task Build authentication system", conn_state)
      assert length(result) == 2

      [event_msg, status_msg] = result
      assert event_msg.type == "event"
      assert event_msg.event == "task_created"
      assert event_msg.title == "Build authentication system"
      assert status_msg.type == "status"
    end
  end

  describe "handle/2 - /approve" do
    test "approves a task by ID", %{conn_state: conn_state} do
      # First create a task
      {:ok, task} = Shazam.TaskBoard.create(%{
        title: "Test task",
        assigned_to: "pm",
        created_by: "human",
        company: "test_co"
      })

      task_id = task.id

      result = WebSocketCommands.handle("/approve #{task_id}", conn_state)
      assert length(result) == 2
      [event_msg, _status] = result
      assert event_msg.type == "event"
      assert event_msg.event == "task_approved"
    end
  end

  describe "handle/2 - /stop" do
    test "returns info when no agents running", %{conn_state: conn_state} do
      # Use a company name that doesn't have RalphLoop running
      state = %{conn_state | company: "nonexistent_co_#{System.unique_integer([:positive])}"}
      result = WebSocketCommands.handle("/stop", state)
      assert [msg] = result
      assert msg.type == "event"
      assert msg.title =~ "No agents running"
    end
  end

  describe "handle/2 - /status" do
    test "returns status message", %{conn_state: conn_state} do
      result = WebSocketCommands.handle("/status", conn_state)
      assert [msg] = result
      assert msg.type == "status"
      assert is_binary(msg.company)
      assert is_integer(msg.agents_total)
    end
  end

  describe "handle/2 - /clear" do
    test "returns clear message", %{conn_state: conn_state} do
      result = WebSocketCommands.handle("/clear", conn_state)
      assert [%{type: "clear"}] = result
    end
  end

  describe "handle/2 - /quit" do
    test "returns quit message", %{conn_state: conn_state} do
      result = WebSocketCommands.handle("/quit", conn_state)
      assert [%{type: "quit"}] = result
    end
  end

  describe "handle/2 - /plan" do
    test "creates a plan task", %{conn_state: conn_state} do
      result = WebSocketCommands.handle("/plan Build a new login page", conn_state)
      assert length(result) == 2
      [task_msg, info_msg] = result
      assert task_msg.type == "event"
      assert task_msg.event == "task_created"
      assert info_msg.type == "event"
      assert info_msg.title =~ "plan"
    end

    test "/plan --list returns plans list", %{conn_state: conn_state} do
      result = WebSocketCommands.handle("/plan --list", conn_state)
      assert is_list(result)
    end
  end

  describe "handle/2 - unknown command" do
    test "returns error for unknown slash command", %{conn_state: conn_state} do
      result = WebSocketCommands.handle("/foobar", conn_state)
      assert [msg] = result
      assert msg.type == "event"
      assert msg.event == "error"
      assert msg.title =~ "Unknown command"
    end
  end

  describe "handle/2 - plain text" do
    test "treats non-command text as task creation", %{conn_state: conn_state} do
      result = WebSocketCommands.handle("Fix the login bug", conn_state)
      assert length(result) == 2
      [event_msg, _status] = result
      assert event_msg.event == "task_created"
      assert event_msg.title == "Fix the login bug"
    end
  end

  describe "handle/2 - /search" do
    test "searches tasks by title", %{conn_state: conn_state} do
      Shazam.TaskBoard.create(%{
        title: "Build authentication module",
        assigned_to: "dev1",
        created_by: "human",
        company: "test_co"
      })

      result = WebSocketCommands.handle("/search authentication", conn_state)
      assert is_list(result)
      assert length(result) >= 1
    end

    test "returns info when no matches", %{conn_state: conn_state} do
      result = WebSocketCommands.handle("/search zzz_nonexistent_zzz", conn_state)
      assert [msg] = result
      assert msg.title =~ "No tasks matching"
    end
  end

  describe "handle/2 - /config" do
    test "returns config info", %{conn_state: conn_state} do
      result = WebSocketCommands.handle("/config", conn_state)
      assert [msg] = result
      assert msg.type == "config"
      assert is_list(msg.entries)
    end
  end

  describe "handle/2 - /agents" do
    test "returns agent list", %{conn_state: conn_state} do
      result = WebSocketCommands.handle("/agents", conn_state)
      assert [msg] = result
      assert msg.type == "agent_list"
      assert length(msg.agents) == 2
    end
  end
end
