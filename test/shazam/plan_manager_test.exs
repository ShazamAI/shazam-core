defmodule Shazam.PlanManagerTest do
  use ExUnit.Case, async: true

  alias Shazam.PlanManager

  @moduletag :plan_manager

  # ── parse_plan_from_output/2 ───────────────────────────────

  describe "parse_plan_from_output/2 with valid JSON block" do
    @valid_json_output """
    Here is the plan:

    ```json
    {
      "title": "Add Auth Feature",
      "summary": "Implement JWT-based authentication for the API.",
      "architecture": {
        "files_created": ["lib/auth.ex"],
        "files_modified": ["lib/router.ex"],
        "interactions": "Auth plugs into the router pipeline",
        "decisions": [{"decision": "Use JWT", "reason": "Stateless auth"}],
        "dependencies": ["joken"]
      },
      "phases": [
        {
          "name": "Phase 1: Foundation",
          "goal": "Auth module created and tested",
          "tasks": [
            {
              "title": "Create auth module",
              "assigned_to": "dev1",
              "depends_on": null,
              "description": "Create lib/auth.ex with JWT signing and verification.",
              "files": ["lib/auth.ex"],
              "acceptance_criteria": ["JWT tokens can be generated", "Tokens can be verified"],
              "complexity": "medium"
            }
          ]
        }
      ],
      "risks": [
        {"risk": "Secret key management", "mitigation": "Use env vars"}
      ]
    }
    ```
    """

    test "parses valid JSON block into a plan map" do
      {:ok, plan} = PlanManager.parse_plan_from_output("plan_1", @valid_json_output)

      assert plan.id == "plan_1"
      assert plan.title == "Add Auth Feature"
      assert plan.status == "draft"
      assert plan.summary == "Implement JWT-based authentication for the API."
    end

    test "extracts tasks from phases" do
      {:ok, plan} = PlanManager.parse_plan_from_output("plan_1", @valid_json_output)

      assert length(plan.tasks) == 1
      [task] = plan.tasks
      assert task.title == "Create auth module"
      assert task.assigned_to == "dev1"
      assert task.depends_on == nil
      assert task.phase == "Phase 1: Foundation"
      assert task.phase_goal == "Auth module created and tested"
    end

    test "builds rich task description with acceptance criteria" do
      {:ok, plan} = PlanManager.parse_plan_from_output("plan_1", @valid_json_output)

      [task] = plan.tasks
      assert task.description =~ "Create lib/auth.ex"
      assert task.description =~ "Acceptance Criteria"
      assert task.description =~ "JWT tokens can be generated"
      assert task.description =~ "Tokens can be verified"
    end

    test "includes files in task description" do
      {:ok, plan} = PlanManager.parse_plan_from_output("plan_1", @valid_json_output)

      [task] = plan.tasks
      assert task.description =~ "Files: lib/auth.ex"
    end

    test "includes complexity in task description" do
      {:ok, plan} = PlanManager.parse_plan_from_output("plan_1", @valid_json_output)

      [task] = plan.tasks
      assert task.description =~ "Complexity: medium"
    end

    test "extracts architecture metadata" do
      {:ok, plan} = PlanManager.parse_plan_from_output("plan_1", @valid_json_output)

      assert is_map(plan.architecture)
      assert plan.architecture["files_created"] == ["lib/auth.ex"]
    end

    test "extracts risks" do
      {:ok, plan} = PlanManager.parse_plan_from_output("plan_1", @valid_json_output)

      assert length(plan.risks) == 1
      [risk] = plan.risks
      assert risk["risk"] == "Secret key management"
    end

    test "sets created_at as ISO 8601 string" do
      {:ok, plan} = PlanManager.parse_plan_from_output("plan_1", @valid_json_output)

      assert is_binary(plan.created_at)
      assert {:ok, _, _} = DateTime.from_iso8601(plan.created_at)
    end
  end

  describe "parse_plan_from_output/2 with multiple phases" do
    @multi_phase_output """
    ```json
    {
      "title": "Multi-phase Plan",
      "summary": "A plan with multiple phases.",
      "phases": [
        {
          "name": "Phase 1",
          "goal": "Setup",
          "tasks": [
            {"title": "Task A", "assigned_to": "dev1", "depends_on": null, "description": "Do A"}
          ]
        },
        {
          "name": "Phase 2",
          "goal": "Implementation",
          "tasks": [
            {"title": "Task B", "assigned_to": "dev2", "depends_on": "Task A", "description": "Do B"},
            {"title": "Task C", "assigned_to": "qa1", "depends_on": null, "description": "Test C"}
          ]
        }
      ]
    }
    ```
    """

    test "flattens tasks from all phases" do
      {:ok, plan} = PlanManager.parse_plan_from_output("plan_2", @multi_phase_output)

      assert length(plan.tasks) == 3
      titles = Enum.map(plan.tasks, & &1.title)
      assert "Task A" in titles
      assert "Task B" in titles
      assert "Task C" in titles
    end

    test "preserves phase info on each task" do
      {:ok, plan} = PlanManager.parse_plan_from_output("plan_2", @multi_phase_output)

      task_b = Enum.find(plan.tasks, &(&1.title == "Task B"))
      assert task_b.phase == "Phase 2"
      assert task_b.phase_goal == "Implementation"
    end

    test "preserves depends_on references" do
      {:ok, plan} = PlanManager.parse_plan_from_output("plan_2", @multi_phase_output)

      task_b = Enum.find(plan.tasks, &(&1.title == "Task B"))
      assert task_b.depends_on == "Task A"

      task_a = Enum.find(plan.tasks, &(&1.title == "Task A"))
      assert task_a.depends_on == nil
    end
  end

  describe "parse_plan_from_output/2 with invalid input" do
    test "returns error for invalid JSON" do
      output = """
      ```json
      {not valid json at all}
      ```
      """

      assert {:error, _reason} = PlanManager.parse_plan_from_output("plan_x", output)
    end

    test "returns error when no JSON block found" do
      assert {:error, _reason} = PlanManager.parse_plan_from_output("plan_x", "Just some text, no JSON here.")
    end

    test "raises on JSON missing required title field" do
      output = """
      ```json
      {"phases": [{"name": "P1", "goal": "G1", "tasks": []}]}
      ```
      """

      # Missing "title" key — pattern match in parse_plan_from_output raises CaseClauseError
      assert_raise CaseClauseError, fn ->
        PlanManager.parse_plan_from_output("plan_x", output)
      end
    end

    test "raises on JSON missing required phases field" do
      output = """
      ```json
      {"title": "No Phases Plan"}
      ```
      """

      # Missing "phases" key — pattern match raises CaseClauseError
      assert_raise CaseClauseError, fn ->
        PlanManager.parse_plan_from_output("plan_x", output)
      end
    end
  end

  describe "parse_plan_from_output/2 with bare JSON (no code fence)" do
    test "parses raw JSON without code fence" do
      output = ~s|{"title": "Bare Plan", "summary": "No fence.", "phases": [{"name": "P1", "goal": "G", "tasks": [{"title": "T1", "assigned_to": "dev", "depends_on": null, "description": "Desc"}]}]}|

      {:ok, plan} = PlanManager.parse_plan_from_output("bare_1", output)
      assert plan.title == "Bare Plan"
      assert length(plan.tasks) == 1
    end
  end

  describe "parse_plan_from_output/2 task description edge cases" do
    test "uses title as description fallback when description is nil" do
      output = """
      ```json
      {
        "title": "Fallback Plan",
        "phases": [{
          "name": "P1",
          "goal": "G1",
          "tasks": [{"title": "My Task", "assigned_to": "dev", "depends_on": null}]
        }]
      }
      ```
      """

      {:ok, plan} = PlanManager.parse_plan_from_output("fb_1", output)
      [task] = plan.tasks
      assert task.description =~ "My Task"
    end

    test "handles task with empty acceptance_criteria" do
      output = """
      ```json
      {
        "title": "Plan",
        "phases": [{
          "name": "P1",
          "goal": "G1",
          "tasks": [{"title": "T", "assigned_to": "d", "depends_on": null, "description": "D", "acceptance_criteria": []}]
        }]
      }
      ```
      """

      {:ok, plan} = PlanManager.parse_plan_from_output("ac_1", output)
      [task] = plan.tasks
      refute task.description =~ "Acceptance Criteria"
    end

    test "handles task with empty files list" do
      output = """
      ```json
      {
        "title": "Plan",
        "phases": [{
          "name": "P1",
          "goal": "G1",
          "tasks": [{"title": "T", "assigned_to": "d", "depends_on": null, "description": "D", "files": []}]
        }]
      }
      ```
      """

      {:ok, plan} = PlanManager.parse_plan_from_output("f_1", output)
      [task] = plan.tasks
      refute task.description =~ "Files:"
    end

    test "defaults summary, architecture, risks when missing" do
      output = """
      ```json
      {"title": "Minimal", "phases": [{"name": "P1", "goal": "G", "tasks": []}]}
      ```
      """

      {:ok, plan} = PlanManager.parse_plan_from_output("min_1", output)
      assert plan.summary == ""
      assert plan.architecture == %{}
      assert plan.risks == []
    end
  end

  # ── build_plan_prompt/1 ────────────────────────────────────

  describe "build_plan_prompt/1" do
    test "returns a string containing the description" do
      result = PlanManager.build_plan_prompt("Implement user authentication")

      assert is_binary(result)
      assert result =~ "Implement user authentication"
    end

    test "includes plan structure instructions" do
      result = PlanManager.build_plan_prompt("any feature")

      assert result =~ "Summary"
      assert result =~ "Architecture"
      assert result =~ "Phases"
      assert result =~ "Risks"
    end

    test "includes JSON format example" do
      result = PlanManager.build_plan_prompt("build API")

      assert result =~ "```json"
      assert result =~ "title"
      assert result =~ "phases"
      assert result =~ "acceptance_criteria"
    end

    test "mentions agent assignment rules" do
      result = PlanManager.build_plan_prompt("refactor codebase")

      assert result =~ "assigned_to"
      assert result =~ "depends_on"
      assert result =~ "complexity"
    end

    test "result is a non-trivial prompt" do
      result = PlanManager.build_plan_prompt("small task")
      # The prompt should be substantial with instructions
      assert String.length(result) > 500
    end
  end
end
