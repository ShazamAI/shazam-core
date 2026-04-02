defmodule Shazam.DoctorTest do
  use ExUnit.Case, async: false

  @moduletag :doctor

  describe "diagnose/0" do
    test "returns a map with checks, passed, failed, warnings, total, and timestamp" do
      result = Shazam.Doctor.diagnose()

      assert is_map(result)
      assert is_list(result.checks)
      assert is_integer(result.passed)
      assert is_integer(result.failed)
      assert is_integer(result.warnings)
      assert is_integer(result.total)
      assert is_binary(result.timestamp)
      assert result.total == length(result.checks)
      assert result.passed + result.failed + result.warnings == result.total
    end

    test "all checks return name, status, and message" do
      result = Shazam.Doctor.diagnose()

      for check <- result.checks do
        assert is_binary(check.name), "check missing name: #{inspect(check)}"
        assert check.status in [:ok, :warning, :error], "invalid status in: #{inspect(check)}"
        assert is_binary(check.message), "check missing message: #{inspect(check)}"
      end
    end

    test "status values are only :ok, :warning, or :error" do
      result = Shazam.Doctor.diagnose()
      statuses = Enum.map(result.checks, & &1.status) |> Enum.uniq()

      for status <- statuses do
        assert status in [:ok, :warning, :error]
      end
    end

    test "timestamp is valid ISO 8601" do
      result = Shazam.Doctor.diagnose()
      assert {:ok, _, _} = DateTime.from_iso8601(result.timestamp)
    end

    test "includes expected check names" do
      result = Shazam.Doctor.diagnose()
      names = Enum.map(result.checks, & &1.name)

      expected = [
        "Claude CLI",
        "Daemon",
        "Workspace",
        "API Port",
        "GenServers",
        "Sessions",
        "Orphaned Processes",
        "Store",
        "TaskBoard",
        "Companies",
        "Disk Store"
      ]

      for name <- expected do
        assert name in names, "Missing check: #{name}"
      end
    end
  end
end
