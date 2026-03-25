defmodule Shazam.AgentPresetsTest do
  use ExUnit.Case, async: true

  alias Shazam.AgentPresets

  @moduletag :agent_presets

  @known_ids [
    "designer",
    "senior_dev",
    "junior_dev",
    "pm",
    "researcher",
    "qa",
    "devops",
    "writer",
    "market_analyst",
    "pr_reviewer",
    "competitor_analyst"
  ]

  describe "list/0" do
    test "returns a list" do
      assert is_list(AgentPresets.list())
    end

    test "returns all presets" do
      presets = AgentPresets.list()
      assert length(presets) == length(@known_ids)
    end

    test "all presets have required fields" do
      for preset <- AgentPresets.list() do
        assert Map.has_key?(preset, :id), "Missing :id in preset"
        assert Map.has_key?(preset, :label), "Missing :label in preset #{inspect(preset.id)}"
        assert Map.has_key?(preset, :icon), "Missing :icon in preset #{preset.id}"
        assert Map.has_key?(preset, :category), "Missing :category in preset #{preset.id}"
        assert Map.has_key?(preset, :defaults), "Missing :defaults in preset #{preset.id}"
      end
    end

    test "all preset IDs are unique" do
      ids = Enum.map(AgentPresets.list(), & &1.id)
      assert ids == Enum.uniq(ids)
    end

    test "results are sorted by category" do
      presets = AgentPresets.list()
      categories = Enum.map(presets, & &1.category)
      assert categories == Enum.sort(categories)
    end

    test "defaults contain role and budget" do
      for preset <- AgentPresets.list() do
        assert Map.has_key?(preset.defaults, :role),
          "Preset #{preset.id} defaults missing :role"
        assert Map.has_key?(preset.defaults, :budget),
          "Preset #{preset.id} defaults missing :budget"
      end
    end
  end

  describe "get/1" do
    test "returns preset for each known ID" do
      for id <- @known_ids do
        preset = AgentPresets.get(id)
        assert preset != nil, "Expected preset for ID #{id}"
        assert preset.id == id
      end
    end

    test "returns nil for unknown ID" do
      assert AgentPresets.get("nonexistent") == nil
    end

    test "returns nil for nil ID" do
      assert AgentPresets.get(nil) == nil
    end

    test "returned preset has defaults with expected keys" do
      preset = AgentPresets.get("senior_dev")
      assert preset.defaults.role == "Senior Developer"
      assert is_integer(preset.defaults.budget)
      assert is_list(preset.defaults.tools)
      assert is_binary(preset.defaults.system_prompt)
    end

    test "pm preset has correct category" do
      preset = AgentPresets.get("pm")
      assert preset.category == "management"
    end

    test "qa preset has correct role" do
      preset = AgentPresets.get("qa")
      assert preset.defaults.role == "QA Engineer"
    end
  end

  describe "build/2" do
    test "returns {:ok, agent} for valid preset" do
      assert {:ok, agent} = AgentPresets.build("senior_dev")
      assert is_map(agent)
    end

    test "returns {:error, :preset_not_found} for invalid preset" do
      assert {:error, :preset_not_found} = AgentPresets.build("nonexistent")
    end

    test "built agent has all expected keys" do
      {:ok, agent} = AgentPresets.build("senior_dev")

      expected_keys = [
        "name",
        "role",
        "supervisor",
        "domain",
        "budget",
        "heartbeat_interval",
        "tools",
        "skills",
        "modules",
        "system_prompt",
        "model",
        "fallback_model"
      ]

      for key <- expected_keys do
        assert Map.has_key?(agent, key), "Built agent missing key: #{key}"
      end
    end

    test "built agent uses preset defaults" do
      {:ok, agent} = AgentPresets.build("pm")
      assert agent["role"] == "Project Manager"
      assert agent["budget"] == 50_000
      assert agent["tools"] == []
      assert agent["model"] == "claude-haiku-4-5-20251001"
    end

    test "overrides are applied" do
      overrides = %{
        "name" => "my_custom_dev",
        "role" => "Lead Developer",
        "budget" => 500_000,
        "supervisor" => "ceo",
        "domain" => "backend"
      }

      {:ok, agent} = AgentPresets.build("senior_dev", overrides)

      assert agent["name"] == "my_custom_dev"
      assert agent["role"] == "Lead Developer"
      assert agent["budget"] == 500_000
      assert agent["supervisor"] == "ceo"
      assert agent["domain"] == "backend"
    end

    test "partial overrides keep other defaults" do
      {:ok, agent} = AgentPresets.build("senior_dev", %{"name" => "custom_name"})

      assert agent["name"] == "custom_name"
      assert agent["role"] == "Senior Developer"
      assert agent["budget"] == 200_000
    end

    test "default name contains preset_id" do
      {:ok, agent} = AgentPresets.build("qa")
      assert agent["name"] =~ "qa_"
    end

    test "default heartbeat_interval is 60000" do
      {:ok, agent} = AgentPresets.build("researcher")
      assert agent["heartbeat_interval"] == 60_000
    end

    test "default skills and modules are empty lists" do
      {:ok, agent} = AgentPresets.build("writer")
      assert agent["skills"] == []
      assert agent["modules"] == []
    end

    test "supervisor and domain default to nil" do
      {:ok, agent} = AgentPresets.build("devops")
      assert agent["supervisor"] == nil
      assert agent["domain"] == nil
    end

    test "fallback_model defaults to nil" do
      {:ok, agent} = AgentPresets.build("senior_dev")
      assert agent["fallback_model"] == nil
    end

    test "fallback_model can be overridden" do
      {:ok, agent} = AgentPresets.build("senior_dev", %{"fallback_model" => "claude-sonnet-4-6"})
      assert agent["fallback_model"] == "claude-sonnet-4-6"
    end
  end
end
