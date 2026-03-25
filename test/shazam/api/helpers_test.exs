defmodule Shazam.API.HelpersTest do
  use ExUnit.Case, async: true

  alias Shazam.API.Helpers

  @moduletag :api_helpers

  describe "serialize_task/1" do
    @base_task %{
      id: "task-001",
      title: "Build feature",
      description: "Implement the new feature",
      status: :pending,
      assigned_to: "dev1",
      created_by: "pm",
      parent_task_id: nil,
      result: nil,
      created_at: ~U[2026-01-15 10:30:00Z],
      updated_at: ~U[2026-01-15 12:00:00Z]
    }

    test "serializes a basic task map with required fields" do
      result = Helpers.serialize_task(@base_task)

      assert result.id == "task-001"
      assert result.title == "Build feature"
      assert result.description == "Implement the new feature"
      assert result.status == :pending
      assert result.assigned_to == "dev1"
      assert result.created_by == "pm"
      assert result.parent_task_id == nil
      assert result.result == nil
      assert result.created_at == "2026-01-15 10:30:00Z"
      assert result.updated_at == "2026-01-15 12:00:00Z"
    end

    test "deleted_at is nil when not present" do
      result = Helpers.serialize_task(@base_task)
      assert result.deleted_at == nil
    end

    test "deleted_at is serialized as string when present" do
      task = Map.put(@base_task, :deleted_at, ~U[2026-02-01 08:00:00Z])
      result = Helpers.serialize_task(task)
      assert result.deleted_at == "2026-02-01 08:00:00Z"
    end

    test "includes depends_on and company when present" do
      task = @base_task |> Map.put(:depends_on, "task-000") |> Map.put(:company, "acme")
      result = Helpers.serialize_task(task)
      assert result.depends_on == "task-000"
      assert result.company == "acme"
    end

    test "depends_on and company default to nil when missing" do
      result = Helpers.serialize_task(@base_task)
      assert result.depends_on == nil
      assert result.company == nil
    end

    test "does not include pipeline fields when pipeline is nil" do
      result = Helpers.serialize_task(@base_task)
      refute Map.has_key?(result, :pipeline)
      refute Map.has_key?(result, :workflow)
      refute Map.has_key?(result, :current_stage)
      refute Map.has_key?(result, :required_role)
    end

    test "does not include pipeline fields when pipeline has only one stage" do
      task = Map.put(@base_task, :pipeline, [
        %{name: "only_stage", role: "dev", status: :pending, assigned_to: "dev1"}
      ])
      result = Helpers.serialize_task(task)
      refute Map.has_key?(result, :workflow)
      refute Map.has_key?(result, :current_stage)
    end

    test "includes pipeline fields when pipeline has multiple stages" do
      task = @base_task
        |> Map.put(:pipeline, [
          %{name: "design", role: "designer", status: :completed, assigned_to: "designer1",
            completed_by: "designer1", output: "mockup.png",
            started_at: ~U[2026-01-15 10:00:00Z], completed_at: ~U[2026-01-15 11:00:00Z]},
          %{name: "develop", role: "developer", status: :pending, assigned_to: "dev1",
            completed_by: nil, output: nil, started_at: nil, completed_at: nil}
        ])
        |> Map.put(:workflow, "design_develop")
        |> Map.put(:current_stage, "develop")
        |> Map.put(:required_role, "developer")

      result = Helpers.serialize_task(task)

      assert result.workflow == "design_develop"
      assert result.current_stage == "develop"
      assert result.required_role == "developer"
      assert length(result.pipeline) == 2

      [stage1, stage2] = result.pipeline
      assert stage1.name == "design"
      assert stage1.role == "designer"
      assert stage1.status == "completed"
      assert stage1.completed_by == "designer1"
      assert stage1.output == "mockup.png"
      assert stage1.started_at == "2026-01-15 10:00:00Z"
      assert stage1.completed_at == "2026-01-15 11:00:00Z"

      assert stage2.name == "develop"
      assert stage2.status == "pending"
      assert stage2.started_at == nil
      assert stage2.completed_at == nil
    end

    test "date fields are converted to strings" do
      result = Helpers.serialize_task(@base_task)
      assert is_binary(result.created_at)
      assert is_binary(result.updated_at)
    end
  end

  describe "serialize_result/1" do
    test "nil returns nil" do
      assert Helpers.serialize_result(nil) == nil
    end

    test "{:error, reason} returns error map with inspected reason" do
      result = Helpers.serialize_result({:error, :timeout})
      assert result == %{error: ":timeout"}
    end

    test "{:error, string} returns error map" do
      result = Helpers.serialize_result({:error, "connection refused"})
      assert result == %{error: ~s("connection refused")}
    end

    test "binary result is returned as-is" do
      assert Helpers.serialize_result("task completed successfully") == "task completed successfully"
    end

    test "empty binary is returned as-is" do
      assert Helpers.serialize_result("") == ""
    end

    test "other types are inspected" do
      assert Helpers.serialize_result(42) == "42"
      assert Helpers.serialize_result(:ok) == ":ok"
      assert Helpers.serialize_result({:ok, "data"}) == ~s({:ok, "data"})
    end

    test "list is inspected" do
      result = Helpers.serialize_result([1, 2, 3])
      assert result == "[1, 2, 3]"
    end

    test "map is inspected" do
      result = Helpers.serialize_result(%{key: "value"})
      assert is_binary(result)
      assert String.contains?(result, "key")
    end
  end
end
