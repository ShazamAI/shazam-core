defmodule Shazam.HotReload do
  @moduledoc """
  Hot code reload for the Shazam daemon.
  Recompiles and reloads modules without stopping any processes.
  GenServer state, WebSocket connections, and running tasks are preserved.
  """

  require Logger

  @core_modules [
    # Core
    Shazam.Company,
    Shazam.Company.Builder,
    Shazam.RalphLoop,
    Shazam.TaskBoard,
    Shazam.TaskBoard.Persistence,
    Shazam.SessionPool,
    Shazam.Orchestrator,
    Shazam.Orchestrator.Executor,
    Shazam.Orchestrator.Streaming,
    Shazam.Metrics,
    Shazam.AgentPulse,
    Shazam.CircuitBreaker,
    Shazam.ContextManager,
    Shazam.ContextRAG,
    Shazam.GitContext,
    Shazam.AgentQuery,
    Shazam.AgentInbox,
    Shazam.PluginManager,
    Shazam.ProjectRegistry,
    Shazam.FileWatcher,
    Shazam.PlanManager,
    Shazam.QAManager,
    Shazam.Daemon,
    Shazam.Store,
    Shazam.FileLogger,
    Shazam.TaskFiles,

    # Providers
    Shazam.Provider.ClaudeCode,
    Shazam.Provider.Codex,
    Shazam.Provider.Cursor,
    Shazam.Provider.Gemini,
    Shazam.Provider.Resolver,

    # API
    Shazam.API.Router,
    Shazam.API.WebSocket,
    Shazam.API.WebSocketCommands,
    Shazam.API.EventBus,
    Shazam.API.Routes.CompanyRoutes,
    Shazam.API.Routes.TaskRoutes,
    Shazam.API.Routes.RalphRoutes,
    Shazam.API.Routes.WorkspaceRoutes,
    Shazam.API.Routes.SkillRoutes,
    Shazam.API.Routes.MiscRoutes,
    Shazam.API.Routes.ProjectRoutes,
    Shazam.API.Routes.FileRoutes,
  ]

  @doc """
  Recompile and hot-reload all Shazam modules.
  Returns {:ok, results} with details of what was reloaded.
  """
  def reload do
    started_at = System.monotonic_time(:millisecond)

    # Step 1: Recompile the project
    compile_result = recompile()

    # Step 2: Reload each module
    reload_results = Enum.map(@core_modules, fn mod ->
      reload_module(mod)
    end)

    succeeded = Enum.count(reload_results, fn {status, _, _} -> status == :ok end)
    failed = Enum.count(reload_results, fn {status, _, _} -> status == :error end)
    skipped = Enum.count(reload_results, fn {status, _, _} -> status == :skipped end)

    elapsed = System.monotonic_time(:millisecond) - started_at

    Shazam.FileLogger.info("Hot reload completed: #{succeeded} reloaded, #{skipped} skipped, #{failed} failed (#{elapsed}ms)")

    {:ok, %{
      compile: compile_result,
      reloaded: succeeded,
      skipped: skipped,
      failed: failed,
      elapsed_ms: elapsed,
      details: Enum.map(reload_results, fn {status, mod, reason} ->
        %{module: inspect(mod), status: status, reason: reason}
      end)
    }}
  end

  @doc """
  Reload a single module by name.
  """
  def reload_module(mod) do
    try do
      case :code.get_object_code(mod) do
        {^mod, binary, filename} ->
          # Purge old version
          :code.purge(mod)
          # Load new version
          case :code.load_binary(mod, filename, binary) do
            {:module, ^mod} -> {:ok, mod, "reloaded"}
            {:error, reason} -> {:error, mod, inspect(reason)}
          end

        :error ->
          # Module not found in code path — try soft purge + reload from file
          :code.purge(mod)
          case :code.load_file(mod) do
            {:module, ^mod} -> {:ok, mod, "reloaded from file"}
            {:error, reason} -> {:skipped, mod, inspect(reason)}
          end
      end
    rescue
      e -> {:error, mod, Exception.message(e)}
    catch
      _, reason -> {:error, mod, inspect(reason)}
    end
  end

  defp recompile do
    try do
      # Force recompilation
      Mix.Task.reenable("compile")
      Mix.Task.run("compile", ["--force"])
      :ok
    rescue
      e -> {:error, Exception.message(e)}
    catch
      _, reason -> {:error, inspect(reason)}
    end
  end
end
