defmodule Shazam.Daemon do
  @moduledoc """
  Manages daemon lifecycle: PID file, health status, connected clients.
  Only active when SHAZAM_DAEMON=true environment variable is set.
  """

  use GenServer

  @pid_file_path "~/.shazam/daemon.pid"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def daemon_mode? do
    System.get_env("SHAZAM_DAEMON") == "true"
  end

  def port do
    case System.get_env("SHAZAM_PORT") do
      nil -> Application.get_env(:shazam, :port, 4040)
      port_str ->
        case Integer.parse(port_str) do
          {port, _} -> port
          :error -> 4040
        end
    end
  end

  def health do
    GenServer.call(__MODULE__, :health)
  catch
    :exit, _ -> %{status: "offline"}
  end

  @impl true
  def init(_opts) do
    pid_file = Path.expand(@pid_file_path)
    File.mkdir_p!(Path.dirname(pid_file))
    File.write!(pid_file, "#{:os.getpid()}")

    # Log daemon start
    Shazam.FileLogger.init()
    Shazam.FileLogger.info("Daemon started on port #{port()} (PID: #{:os.getpid()})")

    {:ok, %{started_at: DateTime.utc_now(), pid_file: pid_file}}
  end

  @impl true
  def handle_call(:health, _from, state) do
    uptime = DateTime.diff(DateTime.utc_now(), state.started_at, :second)
    memory_mb = div(:erlang.memory(:total), 1_048_576)

    companies = try do
      Registry.select(Shazam.CompanyRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
    catch
      _, _ -> []
    end

    {:reply, %{
      status: "running",
      uptime_seconds: uptime,
      memory_mb: memory_mb,
      port: port(),
      companies: companies,
      pid: to_string(:os.getpid())
    }, state}
  end

  @impl true
  def terminate(_reason, state) do
    File.rm(state.pid_file)
    Shazam.FileLogger.info("Daemon stopped")
    :ok
  end
end
