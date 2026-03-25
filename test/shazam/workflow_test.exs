defmodule Shazam.WorkflowTest do
  use ExUnit.Case, async: true

  @moduletag :workflow

  alias Shazam.Workflow

  describe "default_workflow/0" do
    test "returns single-stage workflow" do
      w = Workflow.default_workflow()
      assert w.name == "default"
      assert length(w.stages) == 1
      assert hd(w.stages).name == "execute"
      assert hd(w.stages).role == "*"
    end
  end

  describe "list_all/1" do
    test "returns built-in workflows" do
      workflows = Workflow.list_all(nil)
      names = Enum.map(workflows, & &1.name)
      assert "default" in names
      assert "feature" in names
      assert "hotfix" in names
      assert "review-only" in names
      assert "docs" in names
    end

    test "feature workflow has 4 stages" do
      workflows = Workflow.list_all(nil)
      feature = Enum.find(workflows, & &1.name == "feature")
      assert length(feature.stages) == 4
      stage_names = Enum.map(feature.stages, & &1.name)
      assert stage_names == ["develop", "review", "qa", "commit"]
    end

    test "hotfix workflow has 3 stages" do
      workflows = Workflow.list_all(nil)
      hotfix = Enum.find(workflows, & &1.name == "hotfix")
      assert length(hotfix.stages) == 3
      stage_names = Enum.map(hotfix.stages, & &1.name)
      assert stage_names == ["develop", "qa", "commit"]
    end
  end

  describe "get/2" do
    test "returns built-in workflow by name" do
      w = Workflow.get("feature")
      assert w.name == "feature"
      assert length(w.stages) == 4
    end

    test "returns nil for unknown workflow" do
      assert Workflow.get("nonexistent") == nil
    end

    test "returns default workflow" do
      w = Workflow.get("default")
      assert w.name == "default"
      assert length(w.stages) == 1
    end
  end

  describe "instantiate_pipeline/1" do
    test "creates pipeline from workflow stages" do
      w = Workflow.get("feature")
      pipeline = Workflow.instantiate_pipeline(w)
      assert length(pipeline) == 4

      first = hd(pipeline)
      assert first.name == "develop"
      assert first.role == "dev"
      assert first.status == :pending
      assert first.assigned_to == nil
      assert first.completed_by == nil
      assert first.output == nil
    end

    test "all stages start as pending" do
      w = Workflow.get("hotfix")
      pipeline = Workflow.instantiate_pipeline(w)
      assert Enum.all?(pipeline, fn s -> s.status == :pending end)
    end
  end

  describe "next_stage/2" do
    test "returns next index" do
      pipeline = make_pipeline(4)
      assert Workflow.next_stage(pipeline, 0) == 1
      assert Workflow.next_stage(pipeline, 1) == 2
      assert Workflow.next_stage(pipeline, 2) == 3
    end

    test "returns nil for last stage" do
      pipeline = make_pipeline(4)
      assert Workflow.next_stage(pipeline, 3) == nil
    end

    test "returns nil for single-stage pipeline" do
      pipeline = make_pipeline(1)
      assert Workflow.next_stage(pipeline, 0) == nil
    end
  end

  describe "reject_target/2" do
    test "returns on_reject stage index" do
      w = Workflow.get("feature")
      # review stage (index 1) has on_reject: "develop" (index 0)
      assert Workflow.reject_target(w, 1) == 0
      # qa stage (index 2) has on_reject: "develop" (index 0)
      assert Workflow.reject_target(w, 2) == 0
    end

    test "returns 0 when no on_reject defined" do
      w = Workflow.get("feature")
      # commit stage (index 3) has on_reject: nil → defaults to 0
      assert Workflow.reject_target(w, 3) == 0
    end
  end

  describe "stage_prompt_suffix/2" do
    test "returns suffix for stage with prompt" do
      w = Workflow.get("feature")
      suffix = Workflow.stage_prompt_suffix(w, 0)
      assert suffix =~ "Implement"
    end

    test "returns nil for invalid index" do
      w = Workflow.get("feature")
      assert Workflow.stage_prompt_suffix(w, 99) == nil
    end
  end

  describe "stage_role/2" do
    test "returns role for stage" do
      w = Workflow.get("feature")
      pipeline = Workflow.instantiate_pipeline(w)
      assert Workflow.stage_role(pipeline, 0) == "dev"
      assert Workflow.stage_role(pipeline, 1) == "reviewer"
      assert Workflow.stage_role(pipeline, 2) == "qa"
      assert Workflow.stage_role(pipeline, 3) == "dev"
    end

    test "returns * for invalid index" do
      pipeline = make_pipeline(1)
      assert Workflow.stage_role(pipeline, 99) == "*"
    end
  end

  describe "has_pipeline?/1" do
    test "returns true for task with multi-stage pipeline" do
      task = %{pipeline: make_pipeline(3), current_stage: 0}
      assert Workflow.has_pipeline?(task)
    end

    test "returns false for task without pipeline" do
      task = %{pipeline: nil, current_stage: nil}
      refute Workflow.has_pipeline?(task)
    end

    test "returns false for single-stage pipeline" do
      task = %{pipeline: make_pipeline(1), current_stage: 0}
      refute Workflow.has_pipeline?(task)
    end
  end

  describe "update_pipeline_stage/3" do
    test "updates stage fields in-place" do
      pipeline = make_pipeline(3)
      updated = Workflow.update_pipeline_stage(pipeline, 0, %{
        status: :completed,
        completed_by: "dev-1",
        output: "Done"
      })

      assert Enum.at(updated, 0).status == :completed
      assert Enum.at(updated, 0).completed_by == "dev-1"
      assert Enum.at(updated, 0).output == "Done"
      # Other stages unchanged
      assert Enum.at(updated, 1).status == :pending
    end
  end

  describe "build_stage_context/2" do
    test "builds context from completed stages" do
      pipeline = [
        %{name: "develop", role: "dev", status: :completed, completed_by: "dev-1",
          output: "Implemented OAuth2", assigned_to: nil, started_at: nil, completed_at: nil},
        %{name: "review", role: "reviewer", status: :in_progress, completed_by: nil,
          output: nil, assigned_to: nil, started_at: nil, completed_at: nil},
        %{name: "qa", role: "qa", status: :pending, completed_by: nil,
          output: nil, assigned_to: nil, started_at: nil, completed_at: nil}
      ]

      context = Workflow.build_stage_context(pipeline, 1)
      assert context =~ "develop"
      assert context =~ "dev-1"
      assert context =~ "Implemented OAuth2"
    end

    test "returns empty for first stage" do
      pipeline = make_pipeline(3)
      context = Workflow.build_stage_context(pipeline, 0)
      assert context == ""
    end
  end

  describe "resolve/2" do
    test "uses task workflow field when set" do
      task = %{workflow: "hotfix"}
      w = Workflow.resolve(task)
      assert w.name == "hotfix"
    end

    test "falls back to default when no workflow specified" do
      task = %{}
      w = Workflow.resolve(task)
      assert w.name == "default"
    end

    test "uses company default_workflow config" do
      task = %{}
      config = %{default_workflow: "feature"}
      w = Workflow.resolve(task, config)
      assert w.name == "feature"
    end

    test "task workflow overrides company default" do
      task = %{workflow: "hotfix"}
      config = %{default_workflow: "feature"}
      w = Workflow.resolve(task, config)
      assert w.name == "hotfix"
    end
  end

  # Helper to create a minimal pipeline
  defp make_pipeline(n) do
    Enum.map(1..n, fn i ->
      %{
        name: "stage_#{i}",
        role: "role_#{i}",
        status: :pending,
        assigned_to: nil,
        completed_by: nil,
        output: nil,
        started_at: nil,
        completed_at: nil
      }
    end)
  end
end
