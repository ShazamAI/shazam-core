defmodule Shazam.FileLoggerTest do
  use ExUnit.Case, async: false

  alias Shazam.FileLogger

  @moduletag :file_logger

  setup do
    # Ensure the log directory exists before each test
    FileLogger.init()
    :ok
  end

  # ── log_dir/0 ────────────────────────────────────────────────

  describe "log_dir/0" do
    test "returns a string path" do
      dir = FileLogger.log_dir()

      assert is_binary(dir)
    end

    test "ends with 'logs'" do
      dir = FileLogger.log_dir()

      assert String.ends_with?(dir, "logs")
    end

    test "contains .shazam in the path" do
      dir = FileLogger.log_dir()

      assert dir =~ ".shazam"
    end
  end

  # ── log_file_path/0 ─────────────────────────────────────────

  describe "log_file_path/0" do
    test "returns a string path" do
      path = FileLogger.log_file_path()

      assert is_binary(path)
    end

    test "contains today's date in YYYY-MM-DD format" do
      path = FileLogger.log_file_path()
      today = Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d")

      assert path =~ today
    end

    test "has shazam- prefix and .log extension" do
      path = FileLogger.log_file_path()
      filename = Path.basename(path)

      assert String.starts_with?(filename, "shazam-")
      assert String.ends_with?(filename, ".log")
    end

    test "is under the log directory" do
      path = FileLogger.log_file_path()

      assert String.starts_with?(path, FileLogger.log_dir())
    end
  end

  # ── info/1 ───────────────────────────────────────────────────

  describe "info/1" do
    test "writes to the log file" do
      msg = "info_test_#{:erlang.unique_integer([:positive])}"
      FileLogger.info(msg)

      content = File.read!(FileLogger.log_file_path())

      assert content =~ msg
    end

    test "includes [info] level tag" do
      msg = "info_level_check_#{:erlang.unique_integer([:positive])}"
      FileLogger.info(msg)

      content = File.read!(FileLogger.log_file_path())

      assert content =~ "[info]"
      assert content =~ msg
    end

    test "includes a timestamp" do
      msg = "info_timestamp_#{:erlang.unique_integer([:positive])}"
      FileLogger.info(msg)

      content = File.read!(FileLogger.log_file_path())
      today = Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d")

      # The log line should contain today's date as part of the timestamp
      lines = String.split(content, "\n")
      matching_line = Enum.find(lines, &(&1 =~ msg))

      assert matching_line != nil
      assert matching_line =~ today
    end
  end

  # ── error/1 ──────────────────────────────────────────────────

  describe "error/1" do
    test "writes to the log file with [error] tag" do
      msg = "error_test_#{:erlang.unique_integer([:positive])}"
      FileLogger.error(msg)

      content = File.read!(FileLogger.log_file_path())

      assert content =~ "[error]"
      assert content =~ msg
    end
  end

  # ── warn/1 ───────────────────────────────────────────────────

  describe "warn/1" do
    test "writes to the log file with [warn] tag" do
      msg = "warn_test_#{:erlang.unique_integer([:positive])}"
      FileLogger.warn(msg)

      content = File.read!(FileLogger.log_file_path())

      assert content =~ "[warn]"
      assert content =~ msg
    end
  end

  # ── debug/1 ──────────────────────────────────────────────────

  describe "debug/1" do
    test "writes to the log file with [debug] tag" do
      msg = "debug_test_#{:erlang.unique_integer([:positive])}"
      FileLogger.debug(msg)

      content = File.read!(FileLogger.log_file_path())

      assert content =~ "[debug]"
      assert content =~ msg
    end
  end

  # ── log/2 ────────────────────────────────────────────────────

  describe "log/2" do
    test "appends to existing log file content" do
      msg1 = "first_msg_#{:erlang.unique_integer([:positive])}"
      msg2 = "second_msg_#{:erlang.unique_integer([:positive])}"

      FileLogger.info(msg1)
      FileLogger.info(msg2)

      content = File.read!(FileLogger.log_file_path())

      assert content =~ msg1
      assert content =~ msg2
    end
  end

  # ── list_logs/0 ──────────────────────────────────────────────

  describe "list_logs/0" do
    test "returns a list" do
      # Ensure at least one log entry exists
      FileLogger.info("list_logs_test")

      logs = FileLogger.list_logs()

      assert is_list(logs)
    end

    test "contains today's log file after writing" do
      FileLogger.info("ensure_log_file_exists")

      logs = FileLogger.list_logs()
      today_file = FileLogger.log_file_path()

      assert today_file in logs
    end
  end
end
