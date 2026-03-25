defmodule Shazam.SubtaskParserTest do
  use ExUnit.Case, async: true

  alias Shazam.SubtaskParser

  @moduletag :subtask_parser

  describe "extract_subtasks_json/1" do
    test "parses valid JSON inside ```json code block" do
      output = """
      Here are the subtasks:

      ```json
      [
        {"title": "Build API", "description": "Create REST endpoints", "assigned_to": "dev1"}
      ]
      ```

      Let me know if you need changes.
      """

      assert {:ok, [subtask]} = SubtaskParser.extract_subtasks_json(output)
      assert subtask["title"] == "Build API"
      assert subtask["description"] == "Create REST endpoints"
      assert subtask["assigned_to"] == "dev1"
    end

    test "parses valid JSON inside ```subtasks code block" do
      output = """
      Planning complete.

      ```subtasks
      [
        {"title": "Write tests", "assigned_to": "qa"}
      ]
      ```
      """

      assert {:ok, [subtask]} = SubtaskParser.extract_subtasks_json(output)
      assert subtask["title"] == "Write tests"
      assert subtask["assigned_to"] == "qa"
    end

    test "parses valid JSON inside bare ``` code block" do
      output = """
      Here you go:

      ```
      [
        {"title": "Deploy", "description": "Ship it"}
      ]
      ```
      """

      assert {:ok, [subtask]} = SubtaskParser.extract_subtasks_json(output)
      assert subtask["title"] == "Deploy"
    end

    test "parses plain JSON array without code block" do
      output = ~s([{"title": "Task A", "description": "Do A", "assigned_to": "dev1"}])

      assert {:ok, [subtask]} = SubtaskParser.extract_subtasks_json(output)
      assert subtask["title"] == "Task A"
    end

    test "parses plain JSON array with surrounding whitespace" do
      output = """

        [{"title": "Whitespace task", "assigned_to": "dev2"}]

      """

      assert {:ok, [subtask]} = SubtaskParser.extract_subtasks_json(output)
      assert subtask["title"] == "Whitespace task"
    end

    test "returns :no_subtasks for invalid JSON in code block" do
      output = """
      ```json
      [{"title": "broken", invalid json here}]
      ```
      """

      assert :no_subtasks = SubtaskParser.extract_subtasks_json(output)
    end

    test "returns :no_subtasks for invalid plain JSON" do
      output = "[not valid json at all"

      assert :no_subtasks = SubtaskParser.extract_subtasks_json(output)
    end

    test "returns :no_subtasks when text has no subtasks" do
      output = "Everything looks good. No tasks to create."

      assert :no_subtasks = SubtaskParser.extract_subtasks_json(output)
    end

    test "returns :no_subtasks for empty string" do
      assert :no_subtasks = SubtaskParser.extract_subtasks_json("")
    end

    test "returns :no_subtasks for non-binary input (nil)" do
      assert :no_subtasks = SubtaskParser.extract_subtasks_json(nil)
    end

    test "returns :no_subtasks for non-binary input (integer)" do
      assert :no_subtasks = SubtaskParser.extract_subtasks_json(42)
    end

    test "parses multiple subtask objects in array" do
      output = """
      ```json
      [
        {"title": "Frontend", "description": "Build UI", "assigned_to": "dev1"},
        {"title": "Backend", "description": "Build API", "assigned_to": "dev2"},
        {"title": "Testing", "description": "Write tests", "assigned_to": "qa"}
      ]
      ```
      """

      assert {:ok, subtasks} = SubtaskParser.extract_subtasks_json(output)
      assert length(subtasks) == 3
      assert Enum.map(subtasks, & &1["title"]) == ["Frontend", "Backend", "Testing"]
    end

    test "parses subtask with all fields" do
      output = """
      ```json
      [
        {
          "title": "Implement auth",
          "description": "Add JWT-based authentication to the API",
          "assigned_to": "senior_dev",
          "depends_on": "task-123"
        }
      ]
      ```
      """

      assert {:ok, [subtask]} = SubtaskParser.extract_subtasks_json(output)
      assert subtask["title"] == "Implement auth"
      assert subtask["description"] == "Add JWT-based authentication to the API"
      assert subtask["assigned_to"] == "senior_dev"
      assert subtask["depends_on"] == "task-123"
    end

    test "parses subtask with minimal fields" do
      output = """
      ```json
      [{"title": "Quick fix"}]
      ```
      """

      assert {:ok, [subtask]} = SubtaskParser.extract_subtasks_json(output)
      assert subtask["title"] == "Quick fix"
      assert subtask["description"] == nil
      assert subtask["assigned_to"] == nil
    end

    test "returns :no_subtasks when JSON is an object instead of array" do
      output = ~s({"title": "Not an array"})

      assert :no_subtasks = SubtaskParser.extract_subtasks_json(output)
    end

    test "returns :no_subtasks when code block contains a JSON object instead of array" do
      output = """
      ```json
      {"title": "Not an array"}
      ```
      """

      assert :no_subtasks = SubtaskParser.extract_subtasks_json(output)
    end
  end
end
