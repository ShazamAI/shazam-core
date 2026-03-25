defmodule Shazam.ProjectRegistryTest do
  use ExUnit.Case, async: false

  @moduletag :project_registry

  setup do
    # Get initial state and restore after test
    initial_projects = Shazam.ProjectRegistry.list()

    on_exit(fn ->
      # Clean up any test projects
      current = Shazam.ProjectRegistry.list()
      Enum.each(current, fn p ->
        if String.starts_with?(p.name, "test_") do
          Shazam.ProjectRegistry.remove(p.name)
        end
      end)
    end)

    %{initial_projects: initial_projects}
  end

  describe "register/1" do
    test "registers a new project" do
      tmp = Path.join(System.tmp_dir!(), "test_proj_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)

      on_exit(fn -> File.rm_rf!(tmp) end)

      assert :ok = Shazam.ProjectRegistry.register(%{
        name: "test_register_proj",
        path: tmp,
        agents_count: 3
      })

      projects = Shazam.ProjectRegistry.list()
      assert Enum.any?(projects, &(&1.name == "test_register_proj"))
    end

    test "upserts by path" do
      tmp = Path.join(System.tmp_dir!(), "test_upsert_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)

      on_exit(fn -> File.rm_rf!(tmp) end)

      Shazam.ProjectRegistry.register(%{name: "test_v1", path: tmp, agents_count: 1})
      Shazam.ProjectRegistry.register(%{name: "test_v2", path: tmp, agents_count: 5})

      projects = Shazam.ProjectRegistry.list()
      matching = Enum.filter(projects, &(&1.path == tmp))
      assert length(matching) == 1
      assert hd(matching).name == "test_v2"
    end
  end

  describe "list/0" do
    test "returns a list of projects with status" do
      projects = Shazam.ProjectRegistry.list()
      assert is_list(projects)

      Enum.each(projects, fn p ->
        assert is_binary(p.name)
        assert p.status in ["running", "stopped"]
      end)
    end
  end

  describe "get/1" do
    test "returns {:ok, project} for existing project" do
      tmp = Path.join(System.tmp_dir!(), "test_get_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)

      Shazam.ProjectRegistry.register(%{name: "test_get_proj", path: tmp})
      assert {:ok, project} = Shazam.ProjectRegistry.get("test_get_proj")
      assert project.name == "test_get_proj"
      assert project.status in ["running", "stopped"]
    end

    test "returns {:error, :not_found} for missing project" do
      assert {:error, :not_found} = Shazam.ProjectRegistry.get("does_not_exist_#{System.unique_integer([:positive])}")
    end
  end

  describe "remove/1" do
    test "removes a project by name" do
      tmp = Path.join(System.tmp_dir!(), "test_rm_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)

      Shazam.ProjectRegistry.register(%{name: "test_removable", path: tmp})
      assert :ok = Shazam.ProjectRegistry.remove("test_removable")

      assert {:error, :not_found} = Shazam.ProjectRegistry.get("test_removable")
    end
  end

  describe "start_project/1" do
    test "returns error for non-existent project" do
      result = Shazam.ProjectRegistry.start_project("nonexistent_#{System.unique_integer([:positive])}")
      assert {:error, :not_found} = result
    end
  end

  describe "stop_project/1" do
    test "returns :ok even for non-running project" do
      tmp = Path.join(System.tmp_dir!(), "test_stop_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)

      Shazam.ProjectRegistry.register(%{name: "test_stop_proj", path: tmp})
      assert :ok = Shazam.ProjectRegistry.stop_project("test_stop_proj")
    end
  end
end
