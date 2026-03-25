defmodule Shazam.HierarchyTest do
  use ExUnit.Case, async: true

  alias Shazam.Hierarchy

  @moduletag :hierarchy

  @agents [
    %{name: "ceo", role: "CEO", supervisor: nil},
    %{name: "pm", role: "Project Manager", supervisor: "ceo"},
    %{name: "dev1", role: "Senior Developer", supervisor: "pm"},
    %{name: "dev2", role: "Junior Developer", supervisor: "pm"},
    %{name: "qa", role: "QA Engineer", supervisor: "pm"}
  ]

  describe "validate_no_cycles/1" do
    test "returns :ok for acyclic hierarchy" do
      assert :ok = Hierarchy.validate_no_cycles(@agents)
    end

    test "returns :ok for flat hierarchy (no supervisors)" do
      agents = [
        %{name: "a", role: "Dev", supervisor: nil},
        %{name: "b", role: "Dev", supervisor: nil},
        %{name: "c", role: "Dev", supervisor: nil}
      ]

      assert :ok = Hierarchy.validate_no_cycles(agents)
    end

    test "detects a simple two-node cycle" do
      agents = [
        %{name: "a", role: "Dev", supervisor: "b"},
        %{name: "b", role: "Dev", supervisor: "a"}
      ]

      assert {:error, {:cycle_detected, cycle_nodes}} = Hierarchy.validate_no_cycles(agents)
      assert "a" in cycle_nodes
      assert "b" in cycle_nodes
    end

    test "detects a three-node cycle" do
      agents = [
        %{name: "a", role: "Dev", supervisor: "c"},
        %{name: "b", role: "Dev", supervisor: "a"},
        %{name: "c", role: "Dev", supervisor: "b"}
      ]

      assert {:error, {:cycle_detected, cycle_nodes}} = Hierarchy.validate_no_cycles(agents)
      assert length(cycle_nodes) == 3
    end

    test "returns :ok when supervisor references non-existent agent" do
      agents = [
        %{name: "a", role: "Dev", supervisor: "nonexistent"},
        %{name: "b", role: "Dev", supervisor: nil}
      ]

      assert :ok = Hierarchy.validate_no_cycles(agents)
    end

    test "returns :ok for single agent" do
      agents = [%{name: "solo", role: "Dev", supervisor: nil}]
      assert :ok = Hierarchy.validate_no_cycles(agents)
    end

    test "returns :ok for empty list" do
      assert :ok = Hierarchy.validate_no_cycles([])
    end
  end

  describe "find_subordinates/2" do
    test "finds direct subordinates" do
      subs = Hierarchy.find_subordinates(@agents, "pm")
      names = Enum.map(subs, & &1.name)

      assert "dev1" in names
      assert "dev2" in names
      assert "qa" in names
      assert length(subs) == 3
    end

    test "returns empty list for leaf agents" do
      assert Hierarchy.find_subordinates(@agents, "dev1") == []
    end

    test "returns empty list for non-existent agent" do
      assert Hierarchy.find_subordinates(@agents, "ghost") == []
    end

    test "CEO has one subordinate" do
      subs = Hierarchy.find_subordinates(@agents, "ceo")
      assert length(subs) == 1
      assert hd(subs).name == "pm"
    end
  end

  describe "find_supervisor/2" do
    test "finds the supervisor of an agent" do
      sup = Hierarchy.find_supervisor(@agents, "dev1")
      assert sup.name == "pm"
    end

    test "returns nil for top-level agent" do
      assert Hierarchy.find_supervisor(@agents, "ceo") == nil
    end

    test "returns nil for non-existent agent" do
      assert Hierarchy.find_supervisor(@agents, "ghost") == nil
    end
  end

  describe "is_superior?/3" do
    test "detects direct supervisor" do
      assert Hierarchy.is_superior?(@agents, "pm", "dev1")
    end

    test "detects indirect supervisor" do
      assert Hierarchy.is_superior?(@agents, "ceo", "dev1")
    end

    test "returns false for non-superior" do
      refute Hierarchy.is_superior?(@agents, "dev1", "pm")
    end

    test "returns false for peers" do
      refute Hierarchy.is_superior?(@agents, "dev1", "dev2")
    end
  end

  describe "chain_of_command/2" do
    test "returns the chain from agent to top" do
      chain = Hierarchy.chain_of_command(@agents, "dev1")
      names = Enum.map(chain, & &1.name)

      assert names == ["pm", "ceo"]
    end

    test "returns empty for top-level agent" do
      assert Hierarchy.chain_of_command(@agents, "ceo") == []
    end
  end

  describe "best_subordinate_for/3" do
    test "matches subordinate by role keywords" do
      result = Hierarchy.best_subordinate_for(@agents, "pm", "QA testing and verification")
      assert result.name == "qa"
    end

    test "returns a subordinate even with no keyword match" do
      result = Hierarchy.best_subordinate_for(@agents, "pm", "something completely unrelated xyz")
      assert result != nil
      assert result.supervisor == "pm"
    end

    test "returns nil when agent has no subordinates" do
      assert Hierarchy.best_subordinate_for(@agents, "dev1", "any task") == nil
    end
  end
end
