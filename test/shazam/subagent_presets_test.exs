defmodule Shazam.SubagentPresetsTest do
  use ExUnit.Case, async: true

  alias Shazam.SubagentPresets

  describe "list/0" do
    test "returns all preset names sorted" do
      names = SubagentPresets.list()
      assert is_list(names)
      assert length(names) > 0
      assert names == Enum.sort(names)
      assert "architect" in names
      assert "executor" in names
      assert "reviewer" in names
      assert "explorer" in names
      assert "test-writer" in names
      assert "debugger" in names
      assert "security-auditor" in names
      assert "docs-writer" in names
      assert "refactorer" in names
      assert "planner" in names
      assert "analyst" in names
      assert "designer" in names
    end
  end

  describe "get/1" do
    test "returns preset by name" do
      preset = SubagentPresets.get("architect")
      assert preset.name == "architect"
      assert preset.default_model == "opus"
      assert preset.readonly == true
      assert is_list(preset.tools)
      assert "Read" in preset.tools
      assert preset.level == 3
      assert is_binary(preset.prompt)
      assert String.contains?(preset.prompt, "Architect")
    end

    test "returns nil for unknown preset" do
      assert SubagentPresets.get("nonexistent") == nil
    end

    test "executor preset is writable with sonnet" do
      preset = SubagentPresets.get("executor")
      assert preset.name == "executor"
      assert preset.default_model == "sonnet"
      assert preset.readonly == false
      assert "Edit" in preset.tools
      assert "Write" in preset.tools
    end

    test "explorer preset uses haiku" do
      preset = SubagentPresets.get("explorer")
      assert preset.default_model == "haiku"
      assert preset.readonly == true
      assert preset.level == 1
    end
  end

  describe "all/0" do
    test "returns all presets as a map" do
      all = SubagentPresets.all()
      assert is_map(all)
      assert map_size(all) == length(SubagentPresets.list())
    end
  end

  describe "build/2" do
    test "returns preset without overrides" do
      assert {:ok, preset} = SubagentPresets.build("architect")
      assert preset.name == "architect"
      assert preset.default_model == "opus"
    end

    test "applies model override" do
      assert {:ok, preset} = SubagentPresets.build("architect", %{"model" => "haiku"})
      assert preset.default_model == "haiku"
    end

    test "applies readonly override" do
      assert {:ok, preset} = SubagentPresets.build("executor", %{"readonly" => true})
      assert preset.readonly == true
    end

    test "applies tools override" do
      assert {:ok, preset} = SubagentPresets.build("explorer", %{"tools" => ["Read", "Grep"]})
      assert preset.tools == ["Read", "Grep"]
    end

    test "applies description override" do
      assert {:ok, preset} = SubagentPresets.build("architect", %{"description" => "Custom desc"})
      assert preset.description == "Custom desc"
    end

    test "applies prompt override" do
      assert {:ok, preset} = SubagentPresets.build("architect", %{"prompt" => "Custom prompt"})
      assert preset.prompt == "Custom prompt"
    end

    test "preserves non-overridden fields" do
      assert {:ok, preset} = SubagentPresets.build("architect", %{"model" => "haiku"})
      assert preset.name == "architect"
      assert preset.readonly == true
      assert preset.level == 3
      assert String.contains?(preset.prompt, "Architect")
    end

    test "returns error for unknown preset" do
      assert {:error, :not_found} = SubagentPresets.build("nonexistent")
    end

    test "works with atom keys for overrides" do
      assert {:ok, preset} = SubagentPresets.build("architect", %{model: "haiku"})
      assert preset.default_model == "haiku"
    end
  end
end
