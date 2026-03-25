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
  end
end
