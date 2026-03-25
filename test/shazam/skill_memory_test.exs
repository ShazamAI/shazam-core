defmodule Shazam.SkillMemoryTest do
  use ExUnit.Case, async: false

  alias Shazam.SkillMemory

  @moduletag :skill_memory

  setup do
    # Create a temporary workspace directory for isolation
    tmp = Path.join(System.tmp_dir!(), "shazam_skill_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(tmp)

    # Store original workspace config and set our temp workspace
    original = Application.get_env(:shazam, :workspace)
    Application.put_env(:shazam, :workspace, tmp)

    on_exit(fn ->
      # Restore original workspace
      if original do
        Application.put_env(:shazam, :workspace, original)
      else
        Application.delete_env(:shazam, :workspace)
      end

      File.rm_rf!(tmp)
    end)

    {:ok, tmp: tmp}
  end

  # ── base_dir/0 ──────────────────────────────────────────────

  describe "base_dir/0" do
    test "returns a string path when workspace is set" do
      dir = SkillMemory.base_dir()

      assert is_binary(dir)
    end

    test "path ends with .shazam/memories" do
      dir = SkillMemory.base_dir()

      assert String.ends_with?(dir, ".shazam/memories")
    end

    test "path is under the configured workspace", %{tmp: tmp} do
      dir = SkillMemory.base_dir()

      assert String.starts_with?(dir, tmp)
    end

    test "returns nil when workspace is not set" do
      original = Application.get_env(:shazam, :workspace)
      Application.delete_env(:shazam, :workspace)

      assert SkillMemory.base_dir() == nil

      # Restore for other tests in the setup on_exit
      if original, do: Application.put_env(:shazam, :workspace, original)
    end
  end

  # ── skill_path/1 ────────────────────────────────────────────

  describe "skill_path/1" do
    test "returns path under base_dir" do
      path = SkillMemory.skill_path("rules/testing.md")
      base = SkillMemory.base_dir()

      assert String.starts_with?(path, base)
    end

    test "appends the relative path correctly" do
      path = SkillMemory.skill_path("agents/pm.md")

      assert String.ends_with?(path, "agents/pm.md")
    end

    test "returns nil when workspace is not set" do
      original = Application.get_env(:shazam, :workspace)
      Application.delete_env(:shazam, :workspace)

      assert SkillMemory.skill_path("anything.md") == nil

      if original, do: Application.put_env(:shazam, :workspace, original)
    end

    test "handles nested paths" do
      path = SkillMemory.skill_path("project/deep/nested/file.md")
      base = SkillMemory.base_dir()

      assert path == Path.join(base, "project/deep/nested/file.md")
    end
  end

  # ── init/0 ──────────────────────────────────────────────────

  describe "init/0" do
    test "creates the memory directory structure", %{tmp: tmp} do
      {:ok, dir} = SkillMemory.init()

      assert dir == Path.join([tmp, ".shazam", "memories"])
      assert File.dir?(Path.join(dir, "project"))
      assert File.dir?(Path.join(dir, "agents"))
      assert File.dir?(Path.join(dir, "rules"))
      assert File.dir?(Path.join(dir, "decisions"))
    end

    test "creates SKILL.md root index" do
      {:ok, dir} = SkillMemory.init()

      skill_path = Path.join(dir, "SKILL.md")
      assert File.exists?(skill_path)

      content = File.read!(skill_path)
      assert content =~ "skill-index"
      assert content =~ "Project Skills"
    end

    test "does not overwrite existing SKILL.md" do
      {:ok, dir} = SkillMemory.init()

      skill_path = Path.join(dir, "SKILL.md")
      File.write!(skill_path, "custom content")

      # Init again
      {:ok, _dir} = SkillMemory.init()

      assert File.read!(skill_path) == "custom content"
    end

    test "returns error when workspace is not set" do
      original = Application.get_env(:shazam, :workspace)
      Application.delete_env(:shazam, :workspace)

      assert SkillMemory.init() == {:error, :no_workspace}

      if original, do: Application.put_env(:shazam, :workspace, original)
    end
  end

  # ── write_skill/3 and read_skill/1 ─────────────────────────

  describe "write_skill/3 and read_skill/1" do
    test "round-trips a skill file" do
      SkillMemory.init()

      frontmatter = %{"name" => "test-skill", "description" => "A test skill", "tags" => "test, unit"}
      content = "This is the skill content."

      :ok = SkillMemory.write_skill("rules/test-skill.md", frontmatter, content)

      {:ok, {fm, body}} = SkillMemory.read_skill("rules/test-skill.md")

      assert fm["name"] == "test-skill"
      assert fm["description"] == "A test skill"
      assert fm["tags"] == "test, unit"
      assert body == content
    end

    test "read_skill returns error for non-existent file" do
      SkillMemory.init()

      assert {:error, :not_found} = SkillMemory.read_skill("nonexistent.md")
    end

    test "read_skill returns error when no workspace" do
      original = Application.get_env(:shazam, :workspace)
      Application.delete_env(:shazam, :workspace)

      assert {:error, :no_workspace} = SkillMemory.read_skill("anything.md")

      if original, do: Application.put_env(:shazam, :workspace, original)
    end

    test "write_skill creates intermediate directories" do
      SkillMemory.init()

      :ok = SkillMemory.write_skill("rules/deep/nested.md", %{"name" => "nested"}, "content")

      assert {:ok, {_fm, "content"}} = SkillMemory.read_skill("rules/deep/nested.md")
    end
  end

  # ── read_agent/1 and write_agent/2 ─────────────────────────

  describe "read_agent/1 and write_agent/2" do
    test "writes and reads agent memory" do
      SkillMemory.init()

      SkillMemory.write_agent("senior_backend", "I handle backend logic.")

      content = SkillMemory.read_agent("senior_backend")

      assert content == "I handle backend logic."
    end

    test "returns empty string for non-existent agent" do
      SkillMemory.init()

      assert SkillMemory.read_agent("nonexistent_agent") == ""
    end
  end

  # ── list_all/0 ──────────────────────────────────────────────

  describe "list_all/0" do
    test "returns list of skill maps after init" do
      SkillMemory.init()

      skills = SkillMemory.list_all()

      assert is_list(skills)
      # At least SKILL.md should be present
      assert length(skills) >= 1

      paths = Enum.map(skills, & &1.path)
      assert "SKILL.md" in paths
    end

    test "includes written skills" do
      SkillMemory.init()
      SkillMemory.write_skill("rules/my-rule.md", %{"name" => "my-rule", "tags" => "test"}, "Rule content")

      skills = SkillMemory.list_all()
      paths = Enum.map(skills, & &1.path)

      assert "rules/my-rule.md" in paths
    end

    test "each skill has required keys" do
      SkillMemory.init()

      [skill | _] = SkillMemory.list_all()

      assert Map.has_key?(skill, :path)
      assert Map.has_key?(skill, :name)
      assert Map.has_key?(skill, :description)
      assert Map.has_key?(skill, :tags)
      assert Map.has_key?(skill, :content)
      assert Map.has_key?(skill, :size)
    end

    test "returns empty list when no workspace" do
      original = Application.get_env(:shazam, :workspace)
      Application.delete_env(:shazam, :workspace)

      assert SkillMemory.list_all() == []

      if original, do: Application.put_env(:shazam, :workspace, original)
    end
  end
end
