defmodule Shazam.TaskFilesTest do
  use ExUnit.Case, async: true

  alias Shazam.TaskFiles

  @moduletag :task_files

  setup do
    tmp = Path.join(System.tmp_dir!(), "shazam_taskfiles_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    original_workspace = Application.get_env(:shazam, :workspace)
    Application.put_env(:shazam, :workspace, tmp)

    on_exit(fn ->
      if original_workspace do
        Application.put_env(:shazam, :workspace, original_workspace)
      else
        Application.delete_env(:shazam, :workspace)
      end
      File.rm_rf!(tmp)
    end)

    %{workspace: tmp}
  end

  # ── write_task + read_all round-trip ─────────────────

  describe "write_task/1 and read_all/0" do
    test "writes and reads back a task" do
      task = %{
        id: "task-001",
        title: "Build feature",
        description: "Implement the feature",
        status: :pending,
        assigned_to: "dev1",
        created_by: "pm",
        company: "acme",
        parent_task_id: nil,
        result: nil,
        created_at: ~U[2026-01-15 10:30:00Z],
        updated_at: ~U[2026-01-15 12:00:00Z]
      }

      path = TaskFiles.write_task(task)
      assert File.exists?(path)
      assert String.ends_with?(path, "task-001.md")

      tasks = TaskFiles.read_all()
      assert length(tasks) == 1
      [loaded] = tasks
      assert loaded.id == "task-001"
      assert loaded.title == "Build feature"
      assert loaded.status == "pending"
      assert loaded.assigned_to == "dev1"
      assert loaded.created_by == "pm"
      assert loaded.company == "acme"
      assert loaded.description =~ "Implement the feature"
    end

    test "writes task with result" do
      task = %{
        id: "task-002",
        title: "Done task",
        description: "Already done",
        status: :completed,
        assigned_to: "dev1",
        created_by: "pm",
        result: "All tests pass, feature deployed successfully.",
        created_at: ~U[2026-01-15 10:00:00Z],
        updated_at: ~U[2026-01-15 11:00:00Z]
      }

      TaskFiles.write_task(task)
      tasks = TaskFiles.read_all()
      [loaded] = tasks
      assert loaded.result =~ "All tests pass"
    end

    test "handles title with quotes" do
      task = %{
        id: "task-003",
        title: ~s(Fix "critical" bug),
        description: "Fix it",
        status: :pending,
        assigned_to: "dev1",
        created_by: "pm",
        result: nil,
        created_at: ~U[2026-01-15 10:00:00Z],
        updated_at: ~U[2026-01-15 11:00:00Z]
      }

      TaskFiles.write_task(task)
      tasks = TaskFiles.read_all()
      assert length(tasks) == 1
    end

    test "reads multiple tasks" do
      for i <- 1..3 do
        task = %{
          id: "multi-#{i}",
          title: "Task #{i}",
          description: "Description #{i}",
          status: :pending,
          assigned_to: "dev#{i}",
          created_by: "pm",
          result: nil,
          created_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now()
        }
        TaskFiles.write_task(task)
      end

      tasks = TaskFiles.read_all()
      assert length(tasks) == 3
      ids = Enum.map(tasks, & &1.id)
      assert "multi-1" in ids
      assert "multi-2" in ids
      assert "multi-3" in ids
    end
  end

  # ── read_all with empty dir ─────────────────────────

  describe "read_all/0 with no tasks" do
    test "returns empty list when tasks dir doesn't exist yet" do
      assert TaskFiles.read_all() == []
    end
  end

  # ── delete_task ─────────────────────────────────────

  describe "delete_task/1" do
    test "deletes a task file" do
      task = %{
        id: "delete-me",
        title: "Deletable",
        description: "Will be deleted",
        status: :pending,
        assigned_to: "dev1",
        created_by: "pm",
        result: nil,
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }

      TaskFiles.write_task(task)
      assert length(TaskFiles.read_all()) == 1

      TaskFiles.delete_task("delete-me")

      tasks_dir = TaskFiles.tasks_dir()
      path = Path.join(tasks_dir, "delete-me.md")
      refute File.exists?(path)
    end

    test "is a no-op for nonexistent task" do
      TaskFiles.delete_task("nonexistent-task")
      # Should not raise
    end
  end

  # ── update_status ───────────────────────────────────

  describe "update_status/3" do
    test "updates status of existing task" do
      task = %{
        id: "status-update",
        title: "Status task",
        description: "Will change status",
        status: :pending,
        assigned_to: "dev1",
        created_by: "pm",
        result: nil,
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }

      TaskFiles.write_task(task)
      TaskFiles.update_status("status-update", :completed, "Done!")

      tasks = TaskFiles.read_all()
      [loaded] = tasks
      assert loaded.status == "completed"
      assert loaded.result =~ "Done!"
    end

    test "is a no-op for nonexistent task" do
      # Should not raise
      TaskFiles.update_status("nonexistent", :completed, "result")
    end
  end

  # ── sync_to_files ───────────────────────────────────

  describe "sync_to_files/1" do
    test "writes multiple tasks to disk" do
      tasks = for i <- 1..2 do
        %{
          id: "sync-#{i}",
          title: "Sync Task #{i}",
          description: "Desc #{i}",
          status: :pending,
          assigned_to: "dev#{i}",
          created_by: "pm",
          result: nil,
          created_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now()
        }
      end

      TaskFiles.sync_to_files(tasks)

      loaded = TaskFiles.read_all()
      assert length(loaded) == 2
    end
  end

  # ── tasks_dir ───────────────────────────────────────

  describe "tasks_dir/0" do
    test "returns a path ending with .shazam/tasks" do
      dir = TaskFiles.tasks_dir()
      assert String.ends_with?(dir, ".shazam/tasks")
    end
  end

  # ── ensure_dir ──────────────────────────────────────

  describe "ensure_dir/0" do
    test "creates the tasks directory" do
      dir = TaskFiles.ensure_dir()
      assert File.dir?(dir)
    end
  end
end
