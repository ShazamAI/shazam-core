defmodule Shazam.MemoryConsolidator do
  @moduledoc """
  Periodically consolidates agent memories to reduce token usage.

  Runs every 24 hours (or on-demand). For each agent:
  1. Reads all context files (.shazam/context/agents/{name}/*.md)
  2. Counts total tokens (chars / 4 estimate)
  3. If over budget, summarizes old entries and replaces with consolidated version
  4. Updates the index file

  Also consolidates project memories (.shazam/memories/project/).
  """

  use GenServer
  require Logger

  @consolidation_interval :timer.hours(24)
  @max_context_tokens 50_000
  @max_memory_tokens 20_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Manually trigger consolidation for all agents."
  def consolidate_all do
    GenServer.call(__MODULE__, :consolidate_all, :timer.minutes(5))
  end

  @doc "Get consolidation status."
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @impl true
  def init(_opts) do
    Process.send_after(self(), :consolidate, :timer.minutes(1))
    {:ok, %{last_run: nil, results: []}}
  end

  @impl true
  def handle_info(:consolidate, state) do
    new_state = run_consolidation(state)
    schedule_next()
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:consolidate_all, _from, state) do
    new_state = run_consolidation(state)
    {:reply, {:ok, new_state.results}, new_state}
  end

  def handle_call(:status, _from, state) do
    {:reply, %{last_run: state.last_run, results: state.results}, state}
  end

  defp schedule_next do
    Process.send_after(self(), :consolidate, @consolidation_interval)
  end

  defp run_consolidation(state) do
    workspace = Shazam.Config.global_workspace()

    if !workspace do
      Logger.debug("[MemoryConsolidator] No workspace configured, skipping")
      state
    else
      results = []

      # Consolidate agent contexts
      context_dir = Path.join(workspace, ".shazam/context/agents")

      results =
        if File.dir?(context_dir) do
          agent_results =
            context_dir
            |> File.ls!()
            |> Enum.filter(&File.dir?(Path.join(context_dir, &1)))
            |> Enum.map(fn agent_name ->
              consolidate_agent_context(workspace, agent_name)
            end)

          results ++ agent_results
        else
          results
        end

      # Consolidate project memories
      project_result = consolidate_project_memories(workspace)
      results = results ++ [project_result]

      Logger.info("[MemoryConsolidator] Consolidation complete: #{length(results)} areas processed")

      %{state | last_run: DateTime.utc_now(), results: results}
    end
  rescue
    e ->
      Logger.warning("[MemoryConsolidator] Consolidation failed: #{Exception.message(e)}")
      state
  end

  defp consolidate_agent_context(workspace, agent_name) do
    dir = Path.join(workspace, ".shazam/context/agents/#{agent_name}")

    if !File.dir?(dir) do
      %{agent: agent_name, type: :context, action: :skipped, reason: "directory not found"}
    else
      files =
        dir
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".md"))
        |> Enum.reject(&(&1 == "index.md"))
        |> Enum.sort()

      total_chars =
        files
        |> Enum.map(fn f ->
          case File.read(Path.join(dir, f)) do
            {:ok, content} -> String.length(content)
            _ -> 0
          end
        end)
        |> Enum.sum()

      estimated_tokens = div(total_chars, 4)

      if estimated_tokens > @max_context_tokens do
        # Keep the most recent files, archive old ones
        to_keep = div(length(files), 2)
        {old_files, _new_files} = Enum.split(files, length(files) - to_keep)

        # Create a consolidated summary of old files
        old_content =
          Enum.map_join(old_files, "\n\n---\n\n", fn f ->
            case File.read(Path.join(dir, f)) do
              {:ok, content} -> "## #{f}\n#{String.slice(content, 0..500)}"
              _ -> ""
            end
          end)

        # Write consolidated file
        summary_path = Path.join(dir, "_consolidated_#{Date.to_iso8601(Date.utc_today())}.md")

        summary_content = """
        ---
        consolidated: true
        date: #{Date.to_iso8601(Date.utc_today())}
        files_merged: #{length(old_files)}
        ---

        # Consolidated Context for #{agent_name}

        #{String.slice(old_content, 0..10_000)}
        """

        File.write!(summary_path, summary_content)

        # Remove old files
        Enum.each(old_files, fn f ->
          File.rm(Path.join(dir, f))
        end)

        # Update index
        update_index(dir, agent_name)

        Logger.info(
          "[MemoryConsolidator] Agent #{agent_name}: consolidated #{length(old_files)} files (#{estimated_tokens} tokens -> ~#{div(estimated_tokens, 2)} tokens)"
        )

        %{
          agent: agent_name,
          type: :context,
          action: :consolidated,
          files_removed: length(old_files),
          tokens_before: estimated_tokens,
          tokens_after: div(estimated_tokens, 2)
        }
      else
        %{agent: agent_name, type: :context, action: :ok, tokens: estimated_tokens, files: length(files)}
      end
    end
  rescue
    e ->
      Logger.warning("[MemoryConsolidator] Failed to consolidate #{agent_name}: #{Exception.message(e)}")
      %{agent: agent_name, type: :context, action: :error, error: Exception.message(e)}
  end

  defp consolidate_project_memories(workspace) do
    dir = Path.join(workspace, ".shazam/memories/project")

    if !File.dir?(dir) do
      %{type: :project_memories, action: :skipped}
    else
      files = dir |> File.ls!() |> Enum.filter(&String.ends_with?(&1, ".md"))

      total_chars =
        files
        |> Enum.map(fn f ->
          case File.read(Path.join(dir, f)) do
            {:ok, content} -> String.length(content)
            _ -> 0
          end
        end)
        |> Enum.sum()

      estimated_tokens = div(total_chars, 4)

      %{
        type: :project_memories,
        action: :ok,
        files: length(files),
        tokens: estimated_tokens,
        needs_consolidation: estimated_tokens > @max_memory_tokens
      }
    end
  rescue
    _ -> %{type: :project_memories, action: :error}
  end

  defp update_index(dir, agent_name) do
    files =
      dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".md"))
      |> Enum.reject(&(&1 == "index.md"))
      |> Enum.sort()

    index_content = """
    # #{agent_name} — Context Index

    ## Topics
    #{Enum.map_join(files, "\n", fn f -> "- [#{f}](#{f})" end)}
    """

    File.write!(Path.join(dir, "index.md"), index_content)
  end
end
