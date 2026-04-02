defmodule Shazam.AgentCollaborationTest do
  use ExUnit.Case, async: false

  alias Shazam.{AgentInbox, SubtaskParser}

  @moduletag :agent_collaboration

  setup do
    # Start AgentInbox if not already running
    case AgentInbox.start_link() do
      {:ok, pid} -> on_exit(fn -> GenServer.stop(pid) end)
      {:error, {:already_started, _}} -> :ok
    end

    :ok
  end

  describe "push_from_agent/3" do
    test "stores message with from field and type :agent_message" do
      AgentInbox.push_from_agent("dev1", "pm", "Please review the auth module")

      # Give the cast time to process
      Process.sleep(10)

      assert AgentInbox.has_pending?("dev1")

      msg = AgentInbox.pop("dev1")
      assert msg != nil
      assert msg.message == "Please review the auth module"
      assert msg.from == "pm"
      assert msg.type == :agent_message
      assert %DateTime{} = msg.timestamp
    end

    test "queues multiple agent messages" do
      AgentInbox.push_from_agent("qa", "dev1", "Tests are ready for review")
      AgentInbox.push_from_agent("qa", "dev2", "I also need your help with integration tests")

      Process.sleep(10)

      messages = AgentInbox.pop_all("qa")
      assert length(messages) == 2
      assert Enum.at(messages, 0).from == "dev1"
      assert Enum.at(messages, 1).from == "dev2"
    end

    test "agent messages coexist with user messages" do
      AgentInbox.push("dev1", "User says hello")
      AgentInbox.push_from_agent("dev1", "pm", "Agent says hello")

      Process.sleep(10)

      messages = AgentInbox.pop_all("dev1")
      assert length(messages) == 2

      # First is user message (no :type field)
      user_msg = Enum.at(messages, 0)
      assert user_msg.message == "User says hello"
      refute Map.has_key?(user_msg, :type)

      # Second is agent message
      agent_msg = Enum.at(messages, 1)
      assert agent_msg.message == "Agent says hello"
      assert agent_msg.type == :agent_message
      assert agent_msg.from == "pm"
    end
  end

  describe "check_for_collaboration/2" do
    test "parses @agent_name message patterns" do
      output = """
      I've completed the API endpoints.
      @qa Please run the integration tests for the auth module.
      @designer The login page needs a new layout.
      """

      # This should send messages to qa and designer
      SubtaskParser.check_for_collaboration(output, "dev1")

      Process.sleep(10)

      assert AgentInbox.has_pending?("qa")
      assert AgentInbox.has_pending?("designer")

      qa_msg = AgentInbox.pop("qa")
      assert qa_msg.from == "dev1"
      assert qa_msg.message =~ "integration tests"

      designer_msg = AgentInbox.pop("designer")
      assert designer_msg.from == "dev1"
      assert designer_msg.message =~ "login page"
    end

    test "does not send message to self" do
      output = "@dev1 reminder to check tests"

      SubtaskParser.check_for_collaboration(output, "dev1")

      Process.sleep(10)

      refute AgentInbox.has_pending?("dev1")
    end

    test "handles output with no collaboration patterns" do
      output = "Everything is done. No help needed."

      # Should not raise or send any messages
      assert :ok = SubtaskParser.check_for_collaboration(output, "dev1")
    end

    test "handles nil output" do
      assert :ok = SubtaskParser.check_for_collaboration(nil, "dev1")
    end

    test "handles empty string output" do
      SubtaskParser.check_for_collaboration("", "dev1")
      Process.sleep(10)
      refute AgentInbox.has_pending?("dev1")
    end
  end
end
