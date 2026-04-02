defmodule Shazam.TaskDedupTest do
  use ExUnit.Case, async: false

  alias Shazam.TaskBoard

  @moduletag :task_dedup

  setup do
    # Ensure TaskBoard GenServer is running (may have been killed by other tests)
    unless GenServer.whereis(Shazam.TaskBoard), do: TaskBoard.start_link([])

    TaskBoard.clear_all()
    :ok
  end

  describe "task deduplication" do
    test "creating same task twice returns the existing one" do
      attrs = %{
        title: "Build login page",
        description: "Implement OAuth login",
        assigned_to: "dev1",
        created_by: "pm",
        company: "test_co"
      }

      {:ok, first} = TaskBoard.create(attrs)
      {:ok, second} = TaskBoard.create(attrs)

      assert first.id == second.id
      assert first.title == second.title
    end

    test "different titles create separate tasks" do
      base = %{assigned_to: "dev1", created_by: "pm", company: "test_co"}

      {:ok, t1} = TaskBoard.create(Map.put(base, :title, "Task A"))
      {:ok, t2} = TaskBoard.create(Map.put(base, :title, "Task B"))

      assert t1.id != t2.id
    end

    test "different assigned_to creates separate tasks" do
      base = %{title: "Shared title", created_by: "pm", company: "test_co"}

      {:ok, t1} = TaskBoard.create(Map.put(base, :assigned_to, "dev1"))
      {:ok, t2} = TaskBoard.create(Map.put(base, :assigned_to, "dev2"))

      assert t1.id != t2.id
    end

    test "completed tasks do not block new ones with same title" do
      attrs = %{
        title: "Deploy service",
        assigned_to: "dev1",
        created_by: "pm",
        company: "test_co"
      }

      {:ok, first} = TaskBoard.create(attrs)
      # Move to in_progress then complete
      {:ok, _} = TaskBoard.checkout(first.id, "dev1")
      {:ok, _} = TaskBoard.complete(first.id, "done")

      # Should create a new task since the first is completed
      {:ok, second} = TaskBoard.create(attrs)
      assert second.id != first.id
    end

    test "failed tasks do not block new ones with same title" do
      attrs = %{
        title: "Flaky task",
        assigned_to: "dev1",
        created_by: "pm",
        company: "test_co"
      }

      {:ok, first} = TaskBoard.create(attrs)
      {:ok, _} = TaskBoard.fail(first.id, "crash")

      {:ok, second} = TaskBoard.create(attrs)
      assert second.id != first.id
    end

    test "force: true bypasses deduplication" do
      attrs = %{
        title: "Forced task",
        assigned_to: "dev1",
        created_by: "pm",
        company: "test_co"
      }

      {:ok, first} = TaskBoard.create(attrs)
      {:ok, second} = TaskBoard.create(Map.put(attrs, :force, true))

      assert first.id != second.id
      assert first.title == second.title
    end

    test "dedup matches across pending and in_progress statuses" do
      attrs = %{
        title: "Long running task",
        assigned_to: "dev1",
        created_by: "pm",
        company: "test_co"
      }

      {:ok, first} = TaskBoard.create(attrs)
      {:ok, _} = TaskBoard.checkout(first.id, "dev1")

      # Task is now in_progress — creating same should return existing
      {:ok, second} = TaskBoard.create(attrs)
      assert second.id == first.id
    end

    test "different companies create separate tasks" do
      base = %{title: "Company task", assigned_to: "dev1", created_by: "pm"}

      {:ok, t1} = TaskBoard.create(Map.put(base, :company, "company_a"))
      {:ok, t2} = TaskBoard.create(Map.put(base, :company, "company_b"))

      assert t1.id != t2.id
    end
  end
end
