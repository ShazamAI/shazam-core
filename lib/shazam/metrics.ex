defmodule Shazam.Metrics do
  @moduledoc """
  In-memory metrics tracking for Shazam agents.

  Tracks per-agent: success/failure counts, average execution time,
  total tokens consumed, estimated cost, and tasks-per-hour rate.

  Uses ETS for fast concurrent reads. Broadcasts updates via EventBus.
  """

  use GenServer
  require Logger

  @table :shazam_metrics
  @cost_per_1k_tokens 0.003

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records a successful task completion for an agent.

  - `agent` — agent name (string)
  - `duration_ms` — how long the task took in milliseconds
  - `tokens` — number of tokens consumed (0 if unknown)
  """
  def record_completion(agent, duration_ms, tokens \\ 0) do
    GenServer.cast(__MODULE__, {:record_completion, agent, duration_ms, tokens})
  end

  @doc "Records a task failure for an agent."
  def record_failure(agent) do
    GenServer.cast(__MODULE__, {:record_failure, agent})
  end

  @doc "Records token usage and cost for an agent."
  def record_tokens(agent, tokens, cost_usd \\ 0.0) do
    GenServer.cast(__MODULE__, {:record_tokens, agent, tokens, cost_usd})
  end

  @doc "Record context window usage for an agent session."
  def record_context(agent_name, input_tokens, output_tokens) do
    GenServer.cast(__MODULE__, {:record_context, agent_name, input_tokens, output_tokens})
  end

  @doc "Sets the display status for an agent (e.g. `\"working\"`, `\"idle\"`)."
  def set_status(agent, status) do
    GenServer.cast(__MODULE__, {:set_status, agent, status})
  end

  @doc "Resets all metrics."
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @doc "Fully clears all metrics (for tests)."
  def reset_all do
    GenServer.call(__MODULE__, :reset_all)
  end

  @doc "Returns metrics for all agents as a map."
  def get_all do
    GenServer.call(__MODULE__, :get_all)
  end

  @doc "Returns metrics for a single agent."
  def get_agent(name) do
    GenServer.call(__MODULE__, {:get_agent, name})
  end

  @doc """
  Check if agent has exceeded their token budget.

  Returns `:ok`, `{:warning, used, budget}` (at 90%+), or `{:exceeded, used, budget}`.
  """
  def check_budget(agent_name) do
    agent_data = get_agent(agent_name)
    tokens_used = if agent_data, do: agent_data[:total_tokens] || 0, else: 0

    budget = get_agent_budget(agent_name)

    cond do
      budget == nil || budget == 0 -> :ok
      tokens_used >= budget -> {:exceeded, tokens_used, budget}
      tokens_used >= budget * 0.9 -> {:warning, tokens_used, budget}
      true -> :ok
    end
  end

  defp get_agent_budget(agent_name) do
    try do
      companies = Registry.select(Shazam.CompanyRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
      Enum.find_value(companies, fn company ->
        agents = Shazam.Company.get_agents(to_string(company))
        case Enum.find(agents, &(&1.name == agent_name)) do
          nil -> nil
          agent -> agent.budget
        end
      end)
    catch
      kind, reason ->
        Logger.debug("[Metrics] Failed to get budget for #{agent_name}: #{inspect(kind)}: #{inspect(reason)}")
        nil
    end
  end

  @doc """
  Returns dashboard-level aggregate stats combining Metrics and TaskBoard data.

  Returns a map with:
  - `avg_task_duration_ms` — average time from task start to completion
  - `tasks_last_hour` — count of tasks completed in the last 60 minutes
  - `tokens_per_task` — average tokens per completed task
  - `retry_rate` — percentage of tasks that were retried (0.0 to 1.0)
  - `total_tasks` — total number of tasks
  - `total_cost` — total estimated cost in USD
  """
  def get_dashboard_stats do
    GenServer.call(__MODULE__, :get_dashboard_stats)
  end

  @doc "Compute performance score for an agent (0-100)."
  def agent_score(agent_name) do
    agent = get_agent(agent_name) || %{}
    completions = agent[:successes] || 0
    failures = agent[:failures] || 0
    total = completions + failures

    if total == 0 do
      %{score: 0, grade: "N/A", completions: 0, failures: 0, success_rate: 0, avg_duration_ms: 0, total_tokens: 0, cost_per_task: 0, suggestion: nil}
    else
      success_rate = completions / total * 100
      avg_duration = agent[:avg_duration_ms] || 0
      total_tokens = agent[:total_tokens] || 0
      cost_per_task = if total > 0, do: total_tokens / total / 1000 * 0.0065, else: 0

      # Score: weighted average
      # 50% success rate + 30% speed (inverse of duration) + 20% cost efficiency
      speed_score = max(0, 100 - avg_duration / 600_000 * 100)
      cost_score = max(0, 100 - cost_per_task / 0.10 * 100)

      score = round(success_rate * 0.5 + speed_score * 0.3 + cost_score * 0.2)
      score = min(100, max(0, score))

      grade = cond do
        score >= 90 -> "A"
        score >= 75 -> "B"
        score >= 60 -> "C"
        score >= 40 -> "D"
        true -> "F"
      end

      suggestion = cond do
        success_rate < 50 -> "High failure rate (#{round(success_rate)}%). Consider upgrading model or reviewing task descriptions."
        avg_duration > 300_000 -> "Slow average completion (#{round(avg_duration / 1000)}s). Consider using a faster model for simple tasks."
        cost_per_task > 0.05 -> "High cost per task ($#{:erlang.float_to_binary(cost_per_task, decimals: 3)}). Consider Haiku for simpler tasks."
        true -> nil
      end

      %{
        score: score,
        grade: grade,
        completions: completions,
        failures: failures,
        success_rate: round(success_rate),
        avg_duration_ms: round(avg_duration),
        total_tokens: total_tokens,
        cost_per_task: cost_per_task,
        suggestion: suggestion
      }
    end
  end

  @doc "Get performance scores for all agents."
  def all_agent_scores do
    case get_all() do
      %{agents: agents} ->
        Enum.map(agents, fn {name, _data} ->
          {name, agent_score(name)}
        end)
        |> Map.new()
      _ -> %{}
    end
  end

  # --- Callbacks ---

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])
    :ets.insert(table, {:__started_at, System.monotonic_time(:millisecond)})

    # Restore saved metrics from disk
    load_metrics(table)

    Logger.info("[Metrics] Started")
    {:ok, %{table: table}}
  end

  @impl true
  def handle_cast({:record_completion, agent, duration_ms, tokens}, state) do
    now = System.monotonic_time(:millisecond)
    update_agent(agent, fn metrics ->
      total_duration = metrics.total_duration_ms + duration_ms
      successes = metrics.successes + 1
      total_tasks = successes + metrics.failures
      new_tokens = metrics.total_tokens + tokens

      %{metrics |
        successes: successes,
        total_duration_ms: total_duration,
        avg_duration_ms: div(total_duration, successes),
        total_tokens: new_tokens,
        estimated_cost: Float.round(new_tokens / 1000 * @cost_per_1k_tokens, 4),
        last_completed_at: now,
        tasks_per_hour: compute_tasks_per_hour(total_tasks, metrics.first_task_at || now, now)
      }
    end)

    broadcast_metrics_update()
    {:noreply, state}
  end

  def handle_cast({:record_failure, agent}, state) do
    now = System.monotonic_time(:millisecond)
    update_agent(agent, fn metrics ->
      failures = metrics.failures + 1
      total_tasks = metrics.successes + failures

      %{metrics |
        failures: failures,
        tasks_per_hour: compute_tasks_per_hour(total_tasks, metrics.first_task_at || now, now)
      }
    end)

    broadcast_metrics_update()
    {:noreply, state}
  end

  def handle_cast({:record_tokens, agent, tokens, cost_usd}, state) do
    update_agent(agent, fn metrics ->
      %{metrics |
        total_tokens: metrics.total_tokens + tokens,
        cost_usd: Float.round((metrics.cost_usd || 0.0) + cost_usd, 6)
      }
    end)
    # Save metrics to disk
    save_metrics()
    {:noreply, state}
  end

  def handle_cast({:set_status, agent, status}, state) do
    update_agent(agent, fn metrics ->
      %{metrics | status: status}
    end)
    {:noreply, state}
  end

  def handle_cast({:record_context, agent_name, input, output}, state) do
    update_agent(agent_name, fn metrics ->
      context = Map.get(metrics, :context, %{last_input: 0, last_output: 0, peak_input: 0})

      updated_context = %{
        last_input: input,
        last_output: output,
        peak_input: max(Map.get(context, :peak_input, 0), input),
        updated_at: DateTime.utc_now()
      }

      Map.put(metrics, :context, updated_context)
    end)

    broadcast_metrics_update()
    {:noreply, state}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    # Reset session metrics but preserve cumulative token/cost data
    now = System.monotonic_time(:millisecond)
    :ets.tab2list(@table)
    |> Enum.each(fn
      {:__started_at, _} -> :ok
      {agent, metrics} ->
        # Keep tokens and cost, reset session counters
        :ets.insert(@table, {agent, %{default_metrics(now) |
          total_tokens: metrics.total_tokens || 0,
          input_tokens: metrics[:input_tokens] || 0,
          output_tokens: metrics[:output_tokens] || 0,
          cost_usd: metrics[:cost_usd] || 0.0,
          successes: metrics.successes || 0,
          failures: metrics.failures || 0
        }})
    end)
    :ets.insert(@table, {:__started_at, now})
    {:reply, :ok, state}
  end

  def handle_call(:reset_all, _from, state) do
    :ets.delete_all_objects(@table)
    now = System.monotonic_time(:millisecond)
    :ets.insert(@table, {:__started_at, now})
    {:reply, :ok, state}
  end

  def handle_call(:get_all, _from, state) do
    agents =
      :ets.tab2list(@table)
      |> Enum.reject(fn {key, _} -> key == :__started_at end)
      |> Enum.map(fn {agent_name, metrics} ->
        {agent_name, serialize_metrics(metrics)}
      end)
      |> Map.new()

    totals = compute_totals(agents)
    {:reply, %{agents: agents, totals: totals}, state}
  end

  def handle_call({:get_agent, name}, _from, state) do
    result =
      case :ets.lookup(@table, name) do
        [{^name, metrics}] -> serialize_metrics(metrics)
        [] -> nil
      end

    {:reply, result, state}
  end

  def handle_call(:get_dashboard_stats, _from, state) do
    # Gather agent metrics from ETS
    agent_entries =
      :ets.tab2list(@table)
      |> Enum.reject(fn {key, _} -> key == :__started_at end)

    # Aggregate metrics totals
    {total_successes, total_failures, total_duration_ms, total_tokens, total_cost} =
      Enum.reduce(agent_entries, {0, 0, 0, 0, 0.0}, fn {_name, m}, {s, f, d, t, c} ->
        {
          s + m.successes,
          f + m.failures,
          d + m.total_duration_ms,
          t + m.total_tokens,
          c + (m.cost_usd || 0.0) + m.estimated_cost
        }
      end)

    total_tasks = total_successes + total_failures

    # Calculate avg task duration (only from successful completions which have duration)
    avg_task_duration_ms = if total_successes > 0, do: div(total_duration_ms, total_successes), else: 0

    # Tokens per task
    tokens_per_task = if total_successes > 0, do: div(total_tokens, total_successes), else: 0

    # Tasks completed in the last hour — query TaskBoard
    tasks_last_hour = try do
      now = DateTime.utc_now()
      one_hour_ago = DateTime.add(now, -3600, :second)

      Shazam.TaskBoard.list(%{status: :completed})
      |> Enum.count(fn task ->
        DateTime.compare(task.updated_at, one_hour_ago) != :lt
      end)
    rescue
      e ->
        Logger.debug("[Metrics] Failed to count tasks last hour: #{Exception.message(e)}")
        0
    catch
      :exit, reason ->
        Logger.debug("[Metrics] Exit counting tasks last hour: #{inspect(reason)}")
        0
    end

    # Retry rate — tasks with retry_count > 0 / total tasks
    retry_rate = try do
      all_tasks = Shazam.TaskBoard.list(%{})
      total = length(all_tasks)
      if total > 0 do
        retried = Enum.count(all_tasks, fn t -> Map.get(t, :retry_count, 0) > 0 end)
        Float.round(retried / total, 4)
      else
        0.0
      end
    rescue
      e ->
        Logger.debug("[Metrics] Failed to compute retry rate: #{Exception.message(e)}")
        0.0
    catch
      :exit, reason ->
        Logger.debug("[Metrics] Exit computing retry rate: #{inspect(reason)}")
        0.0
    end

    stats = %{
      avg_task_duration_ms: avg_task_duration_ms,
      tasks_last_hour: tasks_last_hour,
      tokens_per_task: tokens_per_task,
      retry_rate: retry_rate,
      total_tasks: total_tasks,
      total_cost: Float.round(total_cost, 4)
    }

    {:reply, stats, state}
  end

  # --- Internal ---

  defp default_metrics(now) do
    %{
      successes: 0,
      failures: 0,
      total_duration_ms: 0,
      avg_duration_ms: 0,
      total_tokens: 0,
      input_tokens: 0,
      output_tokens: 0,
      cost_usd: 0.0,
      estimated_cost: 0.0,
      tasks_per_hour: 0.0,
      first_task_at: now,
      last_completed_at: nil,
      status: "idle"
    }
  end

  defp update_agent(agent, update_fn) do
    now = System.monotonic_time(:millisecond)

    current =
      case :ets.lookup(@table, agent) do
        [{^agent, metrics}] -> metrics
        [] -> default_metrics(now)
      end

    updated = update_fn.(current)
    :ets.insert(@table, {agent, updated})
  end

  defp compute_tasks_per_hour(total_tasks, first_task_at, now) do
    elapsed_hours = max((now - first_task_at) / 3_600_000, 0.001)
    Float.round(total_tasks / elapsed_hours, 2)
  end

  defp serialize_metrics(metrics) do
    context = Map.get(metrics, :context, %{last_input: 0, last_output: 0, peak_input: 0})

    %{
      successes: metrics.successes,
      failures: metrics.failures,
      total_tasks: metrics.successes + metrics.failures,
      success_rate: compute_rate(metrics.successes, metrics.successes + metrics.failures),
      avg_duration_ms: metrics.avg_duration_ms,
      total_tokens: metrics.total_tokens,
      estimated_cost: metrics.estimated_cost,
      tasks_per_hour: metrics.tasks_per_hour,
      context: %{
        last_input: Map.get(context, :last_input, 0),
        last_output: Map.get(context, :last_output, 0),
        peak_input: Map.get(context, :peak_input, 0),
        capacity: 200_000,
        usage_percent: context_usage_percent(Map.get(context, :last_input, 0)),
        warning: context_usage_percent(Map.get(context, :last_input, 0)) > 80
      }
    }
  end

  defp context_usage_percent(0), do: 0
  defp context_usage_percent(input_tokens) do
    round(input_tokens / 200_000 * 100)
  end

  defp compute_rate(_successes, 0), do: 0.0
  defp compute_rate(successes, total), do: Float.round(successes / total * 100, 1)

  defp compute_totals(agents) do
    Enum.reduce(agents, %{successes: 0, failures: 0, total_tokens: 0, estimated_cost: 0.0}, fn {_name, m}, acc ->
      %{
        successes: acc.successes + m.successes,
        failures: acc.failures + m.failures,
        total_tokens: acc.total_tokens + m.total_tokens,
        estimated_cost: Float.round(acc.estimated_cost + m.estimated_cost, 4)
      }
    end)
    |> then(fn totals ->
      total_tasks = totals.successes + totals.failures
      Map.put(totals, :total_tasks, total_tasks)
      |> Map.put(:success_rate, compute_rate(totals.successes, total_tasks))
    end)
  end

  defp broadcast_metrics_update do
    Shazam.API.EventBus.broadcast(%{event: "metrics_updated"})
  end

  defp metrics_file do
    workspace = Application.get_env(:shazam, :workspace, File.cwd!())
    Path.join([workspace, ".shazam", "metrics.json"])
  end

  defp save_metrics do
    spawn(fn ->
      try do
        data = :ets.tab2list(@table)
          |> Enum.reject(fn {key, _} -> key == :__started_at end)
          |> Enum.map(fn {agent, metrics} ->
            {to_string(agent), %{
              total_tokens: metrics.total_tokens || 0,
              input_tokens: metrics[:input_tokens] || 0,
              output_tokens: metrics[:output_tokens] || 0,
              cost_usd: metrics[:cost_usd] || 0.0,
              successes: metrics.successes || 0,
              failures: metrics.failures || 0
            }}
          end)
          |> Map.new()

        path = metrics_file()
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, Jason.encode!(data, pretty: true))
      catch
        kind, reason ->
          Logger.debug("[Metrics] Failed to save metrics to disk: #{inspect(kind)}: #{inspect(reason)}")
          :ok
      end
    end)
  end

  defp load_metrics(table) do
    try do
      path = metrics_file()
      case File.read(path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, data} when is_map(data) ->
              now = System.monotonic_time(:millisecond)
              Enum.each(data, fn {agent, metrics} ->
                :ets.insert(table, {agent, %{default_metrics(now) |
                  total_tokens: metrics["total_tokens"] || 0,
                  input_tokens: metrics["input_tokens"] || 0,
                  output_tokens: metrics["output_tokens"] || 0,
                  cost_usd: (metrics["cost_usd"] || 0.0) * 1.0,
                  successes: metrics["successes"] || 0,
                  failures: metrics["failures"] || 0
                }})
              end)
            _ -> :ok
          end
        _ -> :ok
      end
    catch
      kind, reason ->
        Logger.warning("[Metrics] Failed to load metrics from disk: #{inspect(kind)}: #{inspect(reason)}")
        :ok
    end
  end
end
