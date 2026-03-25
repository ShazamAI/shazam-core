defmodule Shazam.Company.BuilderTest do
  use ExUnit.Case, async: true

  alias Shazam.Company.Builder
  alias Shazam.AgentWorker
  import Shazam.Test.Factory

  @moduletag :builder

  # ── build_agent_configs/1 ──────────────────────────────────

  describe "build_agent_configs/1" do
    test "transforms config agents to AgentWorker structs" do
      config = build_company_config(%{name: "AcmeCo"})
      result = Builder.build_agent_configs(config)

      assert length(result) == 3
      assert Enum.all?(result, &is_struct(&1, AgentWorker))
    end

    test "sets company_ref on all agents from config name" do
      config = build_company_config(%{name: "MyCorp"})
      result = Builder.build_agent_configs(config)

      assert Enum.all?(result, fn a -> a.company_ref == "MyCorp" end)
    end

    test "preserves agent names and roles" do
      config = build_company_config(%{
        agents: [
          build_agent(%{name: "alice", role: "Lead Dev"}),
          build_agent(%{name: "bob", role: "QA Engineer"})
        ]
      })

      result = Builder.build_agent_configs(config)
      names = Enum.map(result, & &1.name)

      assert "alice" in names
      assert "bob" in names

      alice = Enum.find(result, &(&1.name == "alice"))
      assert alice.role == "Lead Dev"
    end

    test "applies default heartbeat_interval when not set" do
      config = build_company_config(%{
        agents: [
          %AgentWorker{name: "agent1", role: "Dev", heartbeat_interval: nil}
        ]
      })

      [agent] = Builder.build_agent_configs(config)
      assert agent.heartbeat_interval == 60_000
    end

    test "applies empty list defaults for tools, skills, modules when nil" do
      config = build_company_config(%{
        agents: [
          %AgentWorker{name: "bare", role: "Dev", tools: nil, skills: nil, modules: nil}
        ]
      })

      [agent] = Builder.build_agent_configs(config)
      assert agent.tools == []
      assert agent.skills == []
      assert agent.modules == []
    end

    test "preserves supervisor reference" do
      config = build_company_config(%{
        agents: [
          build_agent(%{name: "pm", role: "PM", supervisor: nil}),
          build_agent(%{name: "dev", role: "Dev", supervisor: "pm"})
        ]
      })

      result = Builder.build_agent_configs(config)
      dev = Enum.find(result, &(&1.name == "dev"))
      assert dev.supervisor == "pm"
    end

    test "preserves domain, model, provider, system_prompt" do
      config = build_company_config(%{
        agents: [
          %AgentWorker{
            name: "specialist",
            role: "Dev",
            domain: "backend",
            model: "claude-sonnet-4-20250514",
            provider: :claude_code,
            system_prompt: "You are a backend specialist."
          }
        ]
      })

      [agent] = Builder.build_agent_configs(config)
      assert agent.domain == "backend"
      assert agent.model == "claude-sonnet-4-20250514"
      assert agent.provider == :claude_code
      assert agent.system_prompt == "You are a backend specialist."
    end

    test "preserves budget value" do
      config = build_company_config(%{
        agents: [build_agent(%{name: "dev", role: "Dev", budget: 200_000})]
      })

      [agent] = Builder.build_agent_configs(config)
      assert agent.budget == 200_000
    end

    test "handles single agent config" do
      config = build_company_config(%{
        agents: [build_agent(%{name: "solo", role: "Fullstack"})]
      })

      result = Builder.build_agent_configs(config)
      assert length(result) == 1
      assert hd(result).name == "solo"
    end
  end

  # ── build_agents_from_raw/2 ────────────────────────────────

  describe "build_agents_from_raw/2" do
    test "handles empty list" do
      assert Builder.build_agents_from_raw([], "Co") == []
    end

    test "passes through AgentWorker structs and updates company_ref" do
      existing = %AgentWorker{
        name: "worker",
        role: "QA",
        supervisor: nil,
        company_ref: "OldCo"
      }

      [result] = Builder.build_agents_from_raw([existing], "NewCo")

      assert is_struct(result, AgentWorker)
      assert result.name == "worker"
      assert result.role == "QA"
      assert result.company_ref == "NewCo"
    end

    test "converts atom-keyed maps to AgentWorker structs" do
      raw = [
        %{name: "dev1", role: "Senior Dev", supervisor: "pm", budget: 50_000}
      ]

      [agent] = Builder.build_agents_from_raw(raw, "TestCo")

      assert is_struct(agent, AgentWorker)
      assert agent.name == "dev1"
      assert agent.role == "Senior Dev"
      assert agent.supervisor == "pm"
      assert agent.budget == 50_000
      assert agent.company_ref == "TestCo"
    end

    test "converts string-keyed maps to AgentWorker structs" do
      raw = [
        %{"name" => "dev2", "role" => "Junior Dev", "supervisor" => "pm", "budget" => 80_000}
      ]

      [agent] = Builder.build_agents_from_raw(raw, "StringCo")

      assert agent.name == "dev2"
      assert agent.role == "Junior Dev"
      assert agent.supervisor == "pm"
      assert agent.budget == 80_000
      assert agent.company_ref == "StringCo"
    end

    test "sets default heartbeat_interval when not provided" do
      raw = [%{name: "a", role: "Dev"}]
      [agent] = Builder.build_agents_from_raw(raw, "Co")

      assert agent.heartbeat_interval == 60_000
    end

    test "sets empty list defaults for tools, skills, modules" do
      raw = [%{name: "a", role: "Dev"}]
      [agent] = Builder.build_agents_from_raw(raw, "Co")

      assert agent.tools == []
      assert agent.skills == []
      assert agent.modules == []
    end

    test "handles mixed list of structs and maps" do
      existing = %AgentWorker{name: "existing", role: "PM", company_ref: "Old"}
      raw_map = %{name: "new_agent", role: "Dev", supervisor: "existing"}

      result = Builder.build_agents_from_raw([existing, raw_map], "MixedCo")

      assert length(result) == 2
      assert Enum.all?(result, &is_struct(&1, AgentWorker))
      assert Enum.all?(result, fn a -> a.company_ref == "MixedCo" end)
    end

    test "preserves model and fallback_model from string keys" do
      raw = [
        %{
          "name" => "agent",
          "role" => "Dev",
          "model" => "claude-sonnet-4-20250514",
          "fallback_model" => "gpt-4o",
          "provider" => "claude_code"
        }
      ]

      [agent] = Builder.build_agents_from_raw(raw, "Co")

      assert agent.model == "claude-sonnet-4-20250514"
      assert agent.fallback_model == "gpt-4o"
      assert agent.provider == "claude_code"
    end

    test "preserves system_prompt" do
      raw = [%{name: "custom", role: "Dev", system_prompt: "Be concise."}]
      [agent] = Builder.build_agents_from_raw(raw, "Co")

      assert agent.system_prompt == "Be concise."
    end
  end
end
