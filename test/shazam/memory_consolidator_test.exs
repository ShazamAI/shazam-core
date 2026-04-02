defmodule Shazam.MemoryConsolidatorTest do
  use ExUnit.Case, async: false

  @moduletag :memory_consolidator

  setup do
    unless GenServer.whereis(Shazam.MemoryConsolidator) do
      Shazam.MemoryConsolidator.start_link([])
    end

    :ok
  end

  describe "status/0" do
    test "returns last_run and results" do
      status = Shazam.MemoryConsolidator.status()
      assert Map.has_key?(status, :last_run)
      assert Map.has_key?(status, :results)
    end
  end

  describe "consolidate_all/0 with no workspace" do
    test "returns ok with empty results when no workspace configured" do
      original = Application.get_env(:shazam, :workspace)
      Application.put_env(:shazam, :workspace, nil)

      on_exit(fn -> Application.put_env(:shazam, :workspace, original) end)

      {:ok, results} = Shazam.MemoryConsolidator.consolidate_all()
      assert is_list(results)
    end
  end

  describe "consolidation with temp directory" do
    setup do
      tmp = Path.join(System.tmp_dir!(), "shazam_consolidator_test_#{:rand.uniform(100_000)}")
      File.rm_rf!(tmp)

      context_dir = Path.join(tmp, ".shazam/context/agents/senior_1")
      memories_dir = Path.join(tmp, ".shazam/memories/project")
      File.mkdir_p!(context_dir)
      File.mkdir_p!(memories_dir)

      original = Application.get_env(:shazam, :workspace)
      Application.put_env(:shazam, :workspace, tmp)

      on_exit(fn ->
        Application.put_env(:shazam, :workspace, original)
        File.rm_rf!(tmp)
      end)

      %{tmp: tmp, context_dir: context_dir, memories_dir: memories_dir}
    end

    test "files under limit are left alone", %{context_dir: dir} do
      # Create a small file (well under 50k tokens)
      File.write!(Path.join(dir, "auth.md"), "Small context about auth.\n")

      {:ok, results} = Shazam.MemoryConsolidator.consolidate_all()

      agent_result = Enum.find(results, fn r -> r[:agent] == "senior_1" end)
      assert agent_result
      assert agent_result.action == :ok
      assert agent_result.files == 1

      # Original file should still exist
      assert File.exists?(Path.join(dir, "auth.md"))
    end

    test "files over limit get consolidated", %{context_dir: dir} do
      # Create many large files to exceed 50k tokens (200k chars)
      # Each file: ~25k chars -> ~6250 tokens, need 9+ files to exceed 50k tokens
      large_content = String.duplicate("Context line with important data about the project.\n", 500)

      for i <- 1..10 do
        name = String.pad_leading("#{i}", 2, "0")
        File.write!(Path.join(dir, "topic_#{name}.md"), large_content)
      end

      {:ok, results} = Shazam.MemoryConsolidator.consolidate_all()

      agent_result = Enum.find(results, fn r -> r[:agent] == "senior_1" end)
      assert agent_result
      assert agent_result.action == :consolidated
      assert agent_result.files_removed > 0
      assert agent_result.tokens_before > 50_000

      # Consolidated file should exist
      consolidated_files =
        dir
        |> File.ls!()
        |> Enum.filter(&String.starts_with?(&1, "_consolidated_"))

      assert length(consolidated_files) == 1

      # Some original files should have been removed
      remaining = dir |> File.ls!() |> Enum.filter(&String.ends_with?(&1, ".md"))
      assert length(remaining) < 12
    end

    test "index is updated after consolidation", %{context_dir: dir} do
      large_content = String.duplicate("Context data about auth tokens and middleware.\n", 500)

      for i <- 1..10 do
        name = String.pad_leading("#{i}", 2, "0")
        File.write!(Path.join(dir, "topic_#{name}.md"), large_content)
      end

      {:ok, _results} = Shazam.MemoryConsolidator.consolidate_all()

      index_path = Path.join(dir, "index.md")
      assert File.exists?(index_path)

      index_content = File.read!(index_path)
      assert String.contains?(index_content, "senior_1")
      assert String.contains?(index_content, "## Topics")
    end

    test "project memories are reported", %{memories_dir: dir} do
      File.write!(Path.join(dir, "overview.md"), "Project overview content.\n")

      {:ok, results} = Shazam.MemoryConsolidator.consolidate_all()

      project_result = Enum.find(results, fn r -> r[:type] == :project_memories end)
      assert project_result
      assert project_result.action == :ok
      assert project_result.files == 1
    end
  end
end
