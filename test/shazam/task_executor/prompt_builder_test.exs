defmodule Shazam.TaskExecutor.PromptBuilderTest do
  use ExUnit.Case, async: true

  alias Shazam.TaskExecutor.PromptBuilder

  @moduletag :prompt_builder

  # ── build_skills_prompt/1 ──────────────────────────────────

  describe "build_skills_prompt/1" do
    test "returns empty string for empty list" do
      assert PromptBuilder.build_skills_prompt([]) == ""
    end

    test "returns empty string for nil" do
      assert PromptBuilder.build_skills_prompt(nil) == ""
    end

    test "formats a single skill map" do
      skills = [%{"name" => "elixir_expert", "content" => "You know Elixir well."}]
      result = PromptBuilder.build_skills_prompt(skills)

      assert result =~ "## Available skills"
      assert result =~ "### elixir_expert"
      assert result =~ "You know Elixir well."
    end

    test "formats multiple skill maps separated by double newlines" do
      skills = [
        %{"name" => "skill_a", "content" => "Content A"},
        %{"name" => "skill_b", "content" => "Content B"}
      ]

      result = PromptBuilder.build_skills_prompt(skills)

      assert result =~ "### skill_a"
      assert result =~ "### skill_b"
      assert result =~ "Content A"
      assert result =~ "Content B"
      # Skills are separated by double newline
      assert result =~ "Content A\n\n### skill_b"
    end
  end

  # ── build_modules_prompt/1 ─────────────────────────────────

  describe "build_modules_prompt/1" do
    test "returns empty string for empty list" do
      assert PromptBuilder.build_modules_prompt([]) == ""
    end

    test "returns empty string for nil" do
      assert PromptBuilder.build_modules_prompt(nil) == ""
    end

    test "formats a single module" do
      modules = [%{"name" => "Auth", "path" => "lib/auth", "description" => "Auth module"}]
      result = PromptBuilder.build_modules_prompt(modules)

      assert result =~ "## Modules under your responsibility"
      assert result =~ "- **Auth**: `lib/auth` --- Auth module" |> String.replace("---", "\u2014") ||
             result =~ "Auth"
      assert result =~ "lib/auth"
      assert result =~ "Auth module"
    end

    test "formats multiple modules as a list" do
      modules = [
        %{"name" => "Auth", "path" => "lib/auth", "description" => "Handles auth"},
        %{"name" => "API", "path" => "lib/api", "description" => "REST endpoints"}
      ]

      result = PromptBuilder.build_modules_prompt(modules)

      assert result =~ "**Auth**"
      assert result =~ "**API**"
      assert result =~ "`lib/auth`"
      assert result =~ "`lib/api`"
    end

    test "uses 'no description' when description is nil" do
      modules = [%{"name" => "Core", "path" => "lib/core", "description" => nil}]
      result = PromptBuilder.build_modules_prompt(modules)

      assert result =~ "no description"
    end
  end

  # ── implementation_instructions/0 ──────────────────────────

  describe "implementation_instructions/0" do
    test "returns a non-empty string" do
      result = PromptBuilder.implementation_instructions()
      assert is_binary(result)
      assert String.length(result) > 0
    end

    test "contains implementation-related keywords" do
      result = PromptBuilder.implementation_instructions()
      assert result =~ "implement"
      assert result =~ "Implementation Rules"
    end

    test "mentions subtasks format" do
      result = PromptBuilder.implementation_instructions()
      assert result =~ "subtasks"
    end
  end

  # ── pm_instructions/0 ─────────────────────────────────────

  describe "pm_instructions/0" do
    test "returns a non-empty string" do
      result = PromptBuilder.pm_instructions()
      assert is_binary(result)
      assert String.length(result) > 0
    end

    test "contains PM-related keywords" do
      result = PromptBuilder.pm_instructions()
      assert result =~ "PM"
      assert result =~ "Manager"
      assert result =~ "sub-tasks"
      assert result =~ "delegate"
    end

    test "contains subtasks JSON format" do
      result = PromptBuilder.pm_instructions()
      assert result =~ "subtasks"
      assert result =~ "assigned_to"
    end
  end

  # ── build_tech_stack_prompt/0 ──────────────────────────────

  describe "build_tech_stack_prompt/0" do
    test "returns a string" do
      result = PromptBuilder.build_tech_stack_prompt()
      assert is_binary(result)
    end
  end

  # ── build_pipeline_context/1 ───────────────────────────────

  describe "build_pipeline_context/1" do
    test "returns empty string when task has no pipeline" do
      task = %{title: "Some task"}
      assert PromptBuilder.build_pipeline_context(task) == ""
    end

    test "returns empty string when pipeline is nil" do
      task = %{title: "Task", pipeline: nil, current_stage: nil, workflow: nil}
      assert PromptBuilder.build_pipeline_context(task) == ""
    end

    test "returns empty string when pipeline has only one stage" do
      task = %{
        pipeline: [%{name: "only_stage", role: "dev"}],
        current_stage: 0,
        workflow: "test_workflow"
      }

      assert PromptBuilder.build_pipeline_context(task) == ""
    end

    test "returns empty string when current_stage is not an integer" do
      task = %{
        pipeline: [%{name: "s1", role: "dev"}, %{name: "s2", role: "qa"}],
        current_stage: nil,
        workflow: "test_workflow"
      }

      assert PromptBuilder.build_pipeline_context(task) == ""
    end

    test "returns pipeline context for multi-stage pipeline at first stage" do
      task = %{
        pipeline: [
          %{name: "develop", role: "dev", status: :pending, output: nil, completed_by: nil,
            assigned_to: nil, started_at: nil, completed_at: nil},
          %{name: "review", role: "reviewer", status: :pending, output: nil, completed_by: nil,
            assigned_to: nil, started_at: nil, completed_at: nil}
        ],
        current_stage: 0,
        workflow: "feature"
      }

      result = PromptBuilder.build_pipeline_context(task)
      assert result =~ "Workflow Pipeline"
      assert result =~ "feature"
      assert result =~ "Stage 1/2"
      assert result =~ "[CURRENT]"
      assert result =~ "[PENDING]"
    end

    test "returns pipeline context with previous stage output" do
      task = %{
        pipeline: [
          %{name: "develop", role: "dev", status: :completed, output: "Implemented the feature",
            completed_by: "dev1", assigned_to: "dev1", started_at: nil, completed_at: nil},
          %{name: "review", role: "reviewer", status: :in_progress, output: nil, completed_by: nil,
            assigned_to: "reviewer1", started_at: nil, completed_at: nil},
          %{name: "qa", role: "qa", status: :pending, output: nil, completed_by: nil,
            assigned_to: nil, started_at: nil, completed_at: nil}
        ],
        current_stage: 1,
        workflow: "feature"
      }

      result = PromptBuilder.build_pipeline_context(task)
      assert result =~ "Stage 2/3"
      assert result =~ "[DONE]"
      assert result =~ "[CURRENT]"
      assert result =~ "Previous Stage Outputs"
      assert result =~ "Implemented the feature"
    end
  end

  # ── build_role_rules/1 ────────────────────────────────

  describe "build_role_rules/1" do
    test "returns testing policy for developer role" do
      profile = %{role: "Senior Developer", company_ref: nil, supervisor: nil, name: "dev1"}
      result = PromptBuilder.build_role_rules(profile)
      assert result =~ "Testing Policy"
      assert result =~ "developer"
      assert result =~ "do NOT write tests"
    end

    test "returns testing policy for programmer role" do
      profile = %{role: "Programmer", company_ref: nil, supervisor: nil, name: "dev1"}
      result = PromptBuilder.build_role_rules(profile)
      assert result =~ "Testing Policy"
    end

    test "returns empty string for PM role" do
      profile = %{role: "Project Manager", company_ref: nil, supervisor: nil, name: "pm"}
      result = PromptBuilder.build_role_rules(profile)
      assert result == ""
    end

    test "returns empty string for nil role" do
      profile = %{role: nil, company_ref: nil, supervisor: nil, name: "agent"}
      result = PromptBuilder.build_role_rules(profile)
      assert result == ""
    end

    test "returns empty string for designer role" do
      profile = %{role: "UI Designer", company_ref: nil, supervisor: nil, name: "designer"}
      result = PromptBuilder.build_role_rules(profile)
      assert result == ""
    end
  end

  # ── build_designer_context/1 ──────────────────────────

  describe "build_designer_context/1" do
    test "returns empty string for non-designer role" do
      profile = %{role: "Developer", company_ref: nil, supervisor: nil, name: "dev"}
      assert PromptBuilder.build_designer_context(profile) == ""
    end

    test "returns empty string for nil role" do
      profile = %{role: nil, company_ref: nil, supervisor: nil, name: "agent"}
      assert PromptBuilder.build_designer_context(profile) == ""
    end
  end

  # ── build_analyst_context/1 ───────────────────────────

  describe "build_analyst_context/1" do
    test "returns empty string for non-analyst role" do
      profile = %{role: "Developer", company_ref: nil, supervisor: nil, name: "dev"}
      assert PromptBuilder.build_analyst_context(profile) == ""
    end

    test "returns empty string for nil role" do
      profile = %{role: nil, company_ref: nil, supervisor: nil, name: "agent"}
      assert PromptBuilder.build_analyst_context(profile) == ""
    end
  end

  # ── build_domain_restriction_prompt/2 ─────────────────

  describe "build_domain_restriction_prompt/2" do
    test "returns empty string when domain is nil" do
      profile = %{domain: nil, name: "dev"}
      assert PromptBuilder.build_domain_restriction_prompt(profile, "company") == ""
    end

    test "returns empty string when domain is empty" do
      profile = %{domain: "", name: "dev"}
      assert PromptBuilder.build_domain_restriction_prompt(profile, "company") == ""
    end

    test "returns empty string when company_name is nil" do
      profile = %{domain: "backend", name: "dev"}
      assert PromptBuilder.build_domain_restriction_prompt(profile, nil) == ""
    end
  end

  # ── pm_instructions/0 with qa_routing ────────────────

  describe "pm_instructions/0 with qa_routing" do
    test "includes QA routing when enabled" do
      original = Application.get_env(:shazam, :qa_routing)
      Application.put_env(:shazam, :qa_routing, true)

      result = PromptBuilder.pm_instructions()
      assert result =~ "QA Routing Rules"

      if original do
        Application.put_env(:shazam, :qa_routing, original)
      else
        Application.delete_env(:shazam, :qa_routing)
      end
    end

    test "excludes QA routing when disabled" do
      original = Application.get_env(:shazam, :qa_routing)
      Application.put_env(:shazam, :qa_routing, false)

      result = PromptBuilder.pm_instructions()
      refute result =~ "QA Routing Rules"

      if original do
        Application.put_env(:shazam, :qa_routing, original)
      else
        Application.delete_env(:shazam, :qa_routing)
      end
    end
  end
end
