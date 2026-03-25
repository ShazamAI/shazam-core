defmodule Shazam.FileLogger do
  @moduledoc """
  File-based logger for Shazam. Writes structured logs to ~/.shazam/logs/.
  Rotates daily. Safe to call from any process.
  """

  @doc "Initializes the log directory."
  def init do
    File.mkdir_p!(log_dir())
  end

  @doc "Returns the log directory path (resolved at runtime)."
  def log_dir, do: Path.expand("~/.shazam/logs")

  @doc "Appends a log line with timestamp, level, and message."
  def log(level, message) do
    file = log_file_path()
    ts = Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d %H:%M:%S")
    line = "[#{ts}] [#{level}] #{message}\n"

    File.write(file, line, [:append])
  rescue
    _ -> :ok
  end

  @doc "Logs at info level."
  def info(msg), do: log(:info, msg)

  @doc "Logs at error level."
  def error(msg), do: log(:error, msg)

  @doc "Logs at warn level."
  def warn(msg), do: log(:warn, msg)

  @doc "Logs at debug level."
  def debug(msg), do: log(:debug, msg)

  @doc "Returns today's log file path."
  def log_file_path do
    date = Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d")
    Path.join(log_dir(), "shazam-#{date}.log")
  end

  @doc "Returns list of available log files."
  def list_logs do
    case File.ls(log_dir()) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".log"))
        |> Enum.sort(:desc)
        |> Enum.map(&Path.join(log_dir(), &1))
      _ -> []
    end
  end

  @doc "Cleans up logs older than `days` days."
  def cleanup(days \\ 7) do
    cutoff = DateTime.add(DateTime.utc_now(), -days * 86400, :second)

    list_logs()
    |> Enum.each(fn path ->
      case File.stat(path) do
        {:ok, %{mtime: mtime}} ->
          file_dt = NaiveDateTime.from_erl!(mtime) |> DateTime.from_naive!("Etc/UTC")
          if DateTime.compare(file_dt, cutoff) == :lt, do: File.rm(path)
        _ -> :ok
      end
    end)
  end
end
