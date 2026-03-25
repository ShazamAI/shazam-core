defmodule Shazam.Company.BuilderTest do
  use ExUnit.Case, async: true

  alias Shazam.Company.Builder
  alias Shazam.AgentWorker

  @moduletag :builder

  describe "build_agents_from_raw/2 with atom keys" do
    test "converts atom-keyed maps to AgentWorker structs" do
      raw = [
        %{name: "dev1", role: "Senior Developer", supervisor: "pm", budget: 50_000},
        %{name: "pm", role: "Project Manager", supervisor: nil}
      ]

      result = Builder.build_agents_from_raw(raw, "TestCo")

      assert length(result) == 2
      assert Enum.all?(result, &is_struct(&1, AgentWorker))

      dev = Enum.find(result, &(&1.name == "dev1"))
      assert dev.role == "Senior Developer"
      assert dev.supervisor == "pm"
      assert dev.budget == 50_000
      assert dev.company_ref == "TestCo"
    end

    test "sets defaults for missing optional fields" do
      raw = [%{name: "agent", role: "Dev"}]
      [agent] = Builder.build_agents_from_raw(raw, "Co")

      assert agent.heartbeat_interval == 60_000
      assert agent.tools == []
      assert agent.skills == []
      assert agent.modules == []
      assert agent.company_ref == "Co"
    end
  end

  describe "build_agents_from_raw/2 with string keys" do
    test "converts string-keyed maps to AgentWorker structs" do
      raw = [
        %{"name" => "dev1", "role" => "Developer", "supervisor" => "pm", "budget" => 100_000}
      ]

      [agent] = Builder.build_agents_from_raw(raw, "StringCo")

      assert agent.name == "dev1"
      assert agent.role == "Developer"
      assert agent.supervisor == "pm"
      assert agent.budget == 100_000
      assert agent.company_ref == "StringCo"
    end
  end

  describe "build_agents_from_raw/2 with AgentWorker structs" do
    test "updates company_ref on existing AgentWorker structs" do
      existing = %AgentWorker{
        name: "worker1",
        role: "QA",
        supervisor: nil,
        company_ref: "OldCo"
      }

      [result] = Builder.build_agents_from_raw([existing], "NewCo")

      assert is_struct(result, AgentWorker)
      assert result.name == "worker1"
      assert result.role == "QA"
      assert result.company_ref == "NewCo"
    end
  end

  describe "build_agents_from_raw/2 edge cases" do
    test "handles empty list" do
      assert Builder.build_agents_from_raw([], "Co") == []
    end

    test "handles maps with only string keys" do
      raw = [%{"name" => "mixed", "role" => "Dev"}]
      [agent] = Builder.build_agents_from_raw(raw, "MixCo")

      assert agent.name == "mixed"
      assert agent.role == "Dev"
    end
  end

  describe "build_agent_configs/1" do
    test "transforms config agents to AgentWorker structs" do
      config = %{
        name: "TestCo",
        agents: [
          %AgentWorker{
            name: "pm",
            role: "Project Manager",
            supervisor: nil,
            domain: "management"
          },
          %AgentWorker{
            name: "dev",
            role: "Developer",
            supervisor: "pm",
            tools: ["Read", "Edit"]
          }
        ]
      }

      result = Builder.build_agent_configs(config)

      assert length(result) == 2
      pm = Enum.find(result, &(&1.name == "pm"))
      assert pm.company_ref == "TestCo"
      assert pm.domain == "management"

      dev = Enum.find(result, &(&1.name == "dev"))
      assert dev.supervisor == "pm"
      assert dev.tools == ["Read", "Edit"]
    end
  end
end
