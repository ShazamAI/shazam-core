defmodule Shazam.AuditLogTest do
  use ExUnit.Case, async: false

  @moduletag :audit_log

  setup do
    # Ensure AuditLog GenServer is running
    unless GenServer.whereis(Shazam.AuditLog), do: Shazam.AuditLog.start_link([])

    # Clean up persisted audit log before each test
    Shazam.Store.delete("audit_log")

    # Restart with clean state
    if pid = GenServer.whereis(Shazam.AuditLog) do
      GenServer.stop(pid)
    end

    {:ok, _} = Shazam.AuditLog.start_link([])
    :ok
  end

  describe "record/2 and recent/1" do
    test "records and retrieves entries" do
      Shazam.AuditLog.record("task_created", %{task_id: "task_1", title: "Test Task"})
      Process.sleep(50)

      entries = Shazam.AuditLog.recent()
      assert length(entries) == 1

      [entry] = entries
      assert entry.action == "task_created"
      assert entry.details == %{task_id: "task_1", title: "Test Task"}
      assert entry.timestamp != nil
      assert entry.id != nil
    end

    test "entries are ordered newest first" do
      Shazam.AuditLog.record("first_action", %{})
      Process.sleep(10)
      Shazam.AuditLog.record("second_action", %{})
      Process.sleep(50)

      entries = Shazam.AuditLog.recent()
      assert length(entries) == 2
      assert Enum.at(entries, 0).action == "second_action"
      assert Enum.at(entries, 1).action == "first_action"
    end

    test "limit restricts number of returned entries" do
      for i <- 1..10 do
        Shazam.AuditLog.record("action_#{i}", %{i: i})
      end

      Process.sleep(100)

      entries = Shazam.AuditLog.recent(3)
      assert length(entries) == 3
    end
  end

  describe "filter/2" do
    test "filters entries by action type" do
      Shazam.AuditLog.record("task_created", %{task_id: "t1"})
      Shazam.AuditLog.record("task_deleted", %{task_id: "t2"})
      Shazam.AuditLog.record("task_created", %{task_id: "t3"})
      Process.sleep(100)

      created = Shazam.AuditLog.filter("task_created")
      assert length(created) == 2
      assert Enum.all?(created, fn e -> e.action == "task_created" end)

      deleted = Shazam.AuditLog.filter("task_deleted")
      assert length(deleted) == 1
    end

    test "filter with limit" do
      for i <- 1..5 do
        Shazam.AuditLog.record("repeated", %{i: i})
      end

      Process.sleep(100)

      entries = Shazam.AuditLog.filter("repeated", 2)
      assert length(entries) == 2
    end

    test "filter returns empty for unknown action" do
      Shazam.AuditLog.record("known_action", %{})
      Process.sleep(50)

      entries = Shazam.AuditLog.filter("unknown_action")
      assert entries == []
    end
  end

  describe "max entries cap" do
    test "caps entries at 1000" do
      # Record more than max entries
      for i <- 1..1010 do
        Shazam.AuditLog.record("bulk_action", %{i: i})
      end

      Process.sleep(200)

      entries = Shazam.AuditLog.recent(2000)
      assert length(entries) == 1000
    end
  end
end
