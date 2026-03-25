defmodule Shazam.TaskTemplatesTest do
  use ExUnit.Case, async: true

  alias Shazam.TaskTemplates

  @moduletag :task_templates

  @required_fields [:id, :name, :icon, :title_pattern, :description_template]

  @known_ids ["bug_fix", "new_feature", "refactoring", "code_review", "documentation", "testing"]

  describe "list/0" do
    test "returns a list" do
      assert is_list(TaskTemplates.list())
    end

    test "returns the correct number of templates" do
      assert length(TaskTemplates.list()) == 6
    end

    test "all templates have required fields" do
      for template <- TaskTemplates.list() do
        for field <- @required_fields do
          assert Map.has_key?(template, field),
            "Template #{template.id} is missing field #{field}"
        end
      end
    end

    test "all template IDs are unique" do
      ids = Enum.map(TaskTemplates.list(), & &1.id)
      assert ids == Enum.uniq(ids)
    end

    test "all template fields are non-empty strings" do
      for template <- TaskTemplates.list() do
        for field <- @required_fields do
          value = Map.get(template, field)
          assert is_binary(value) and value != "",
            "Template #{template.id}.#{field} should be a non-empty string, got: #{inspect(value)}"
        end
      end
    end
  end

  describe "get/1" do
    test "returns template for each known ID" do
      for id <- @known_ids do
        template = TaskTemplates.get(id)
        assert template != nil, "Expected template for ID #{id}"
        assert template.id == id
      end
    end

    test "returns nil for unknown ID" do
      assert TaskTemplates.get("nonexistent") == nil
    end

    test "returns nil for nil ID" do
      assert TaskTemplates.get(nil) == nil
    end

    test "returned template has all required fields" do
      template = TaskTemplates.get("bug_fix")

      for field <- @required_fields do
        assert Map.has_key?(template, field)
      end
    end

    test "bug_fix template has correct name" do
      template = TaskTemplates.get("bug_fix")
      assert template.name == "Bug Fix"
    end

    test "new_feature template has correct title_pattern" do
      template = TaskTemplates.get("new_feature")
      assert template.title_pattern == "Feature: "
    end

    test "description_template contains markdown content" do
      template = TaskTemplates.get("bug_fix")
      assert template.description_template =~ "##"
      assert template.description_template =~ "Acceptance Criteria"
    end
  end
end
