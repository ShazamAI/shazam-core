defmodule Shazam.API.Routes.TaskRoutes do
  @moduledoc "Handles all /api/tasks/* endpoints."

  use Plug.Router

  import Shazam.API.Helpers

  plug :match
  plug :dispatch

  get "/" do
    filters =
      conn.query_params
      |> Enum.reduce(%{}, fn
        {"status", v}, acc -> Map.put(acc, :status, String.to_existing_atom(v))
        {"assigned_to", v}, acc -> Map.put(acc, :assigned_to, v)
        {"company", v}, acc -> Map.put(acc, :company, v)
        _, acc -> acc
      end)

    tasks = Shazam.tasks(filters) |> Enum.map(&serialize_task/1)
    json(conn, 200, %{tasks: tasks})
  end

  # GET /tasks/export?format=json|csv&company=Name
  get "/export" do
    format = conn.params["format"] || "json"
    company = conn.params["company"]

    filter = if company, do: %{company: company}, else: %{}
    tasks = Shazam.TaskBoard.list(filter)

    case format do
      "csv" ->
        csv = tasks_to_csv(tasks)

        conn
        |> put_resp_content_type("text/csv")
        |> put_resp_header(
          "content-disposition",
          "attachment; filename=\"tasks-#{Date.to_iso8601(Date.utc_today())}.csv\""
        )
        |> send_resp(200, csv)

      _ ->
        serialized = Enum.map(tasks, &serialize_task/1)

        json(conn, 200, %{
          tasks: serialized,
          count: length(serialized),
          exported_at: DateTime.to_iso8601(DateTime.utc_now())
        })
    end
  end

  # POST /tasks/import
  post "/import" do
    tasks_raw = conn.body_params["tasks"] || []
    company = conn.body_params["company"]

    if !is_list(tasks_raw) || length(tasks_raw) == 0 do
      json(conn, 400, %{error: "tasks array is required"})
    else
      results =
        Enum.map(tasks_raw, fn t ->
          attrs = %{
            title: t["title"],
            description: t["description"],
            assigned_to: t["assigned_to"],
            company: company || t["company"],
            created_by: t["created_by"] || "import",
            depends_on: t["depends_on"]
          }

          case Shazam.TaskBoard.create(attrs) do
            {:ok, task} -> %{id: task.id, title: task.title, status: "created"}
            {:error, reason} -> %{title: t["title"], status: "error", reason: inspect(reason)}
          end
        end)

      created = Enum.count(results, &(&1.status == "created"))
      json(conn, 200, %{imported: created, total: length(results), results: results})
    end
  end

  # POST /tasks/analyze — analyze complexity without creating
  post "/analyze" do
    analysis = Shazam.TaskComplexity.analyze(conn.body_params)

    case analysis do
      :simple ->
        json(conn, 200, %{complexity: "simple", should_decompose: false})

      {:complex, reasons} ->
        json(conn, 200, %{complexity: "complex", should_decompose: false, reasons: reasons})

      {:suggest_decomposition, reasons, estimated} ->
        json(conn, 200, %{complexity: "high", should_decompose: true, reasons: reasons, estimated_subtasks: estimated})
    end
  end

  get "/deleted" do
    tasks = Shazam.TaskBoard.list(%{status: :deleted, include_deleted: true})
    json(conn, 200, %{tasks: Enum.map(tasks, &serialize_task/1)})
  end

  post "/bulk" do
    %{"action" => action, "task_ids" => task_ids} = conn.body_params

    results =
      Enum.reduce(task_ids, %{ok: [], errors: %{}}, fn task_id, acc ->
        case execute_bulk_action(action, task_id) do
          :ok ->
            %{acc | ok: acc.ok ++ [task_id]}

          {:ok, _} ->
            %{acc | ok: acc.ok ++ [task_id]}

          {:error, reason} ->
            %{acc | errors: Map.put(acc.errors, task_id, inspect(reason))}
        end
      end)

    Shazam.API.EventBus.broadcast(%{
      event: "bulk_action",
      action: action,
      ok: results.ok,
      errors: results.errors
    })

    json(conn, 200, results)
  end

  post "/pause-all" do
    company = conn.body_params["company"] || find_first_company()
    killed_ids = if company do
      {:ok, ids} = Shazam.RalphLoop.pause_all(company)
      ids
    else
      []
    end

    pending = Shazam.TaskBoard.list(%{status: :pending})
    paused_pending = Enum.reduce(pending, 0, fn task, acc ->
      case Shazam.TaskBoard.fail(task.id, "Paused by user") do
        {:ok, _} -> acc + 1
        _ -> acc
      end
    end)

    total = length(killed_ids) + paused_pending
    json(conn, 200, %{status: "ok", paused: total, running_killed: length(killed_ids), pending_paused: paused_pending})
  end

  post "/resume-all" do
    tasks = Shazam.TaskBoard.list(%{status: :failed})
    resumed = Enum.reduce(tasks, 0, fn task, acc ->
      if task.result == "Paused by user" do
        case Shazam.TaskBoard.retry(task.id) do
          {:ok, _} -> acc + 1
          _ -> acc
        end
      else
        acc
      end
    end)

    Shazam.API.EventBus.broadcast(%{event: "tasks_resumed", count: resumed})
    json(conn, 200, %{status: "ok", resumed: resumed})
  end

  get "/:task_id/ancestry" do
    ancestry = Shazam.TaskBoard.goal_ancestry(task_id)
    json(conn, 200, %{ancestry: ancestry})
  end

  post "/:task_id/approve" do
    case Shazam.TaskBoard.approve(task_id) do
      {:ok, task} ->
        Shazam.API.EventBus.broadcast(%{event: "task_approved", task: serialize_task(task)})
        json(conn, 200, serialize_task(task))

      {:error, reason} ->
        json(conn, 422, %{error: inspect(reason)})
    end
  end

  post "/:task_id/reject" do
    reason = (conn.body_params["reason"] || "Rejected by user")

    case Shazam.TaskBoard.reject(task_id, reason) do
      {:ok, task} ->
        Shazam.API.EventBus.broadcast(%{event: "task_rejected", task: serialize_task(task)})
        json(conn, 200, serialize_task(task))

      {:error, reason} ->
        json(conn, 422, %{error: inspect(reason)})
    end
  end

  post "/:task_id/retry" do
    case Shazam.TaskBoard.retry(task_id) do
      {:ok, task} ->
        Shazam.API.EventBus.broadcast(%{event: "task_retried", task: serialize_task(task)})
        json(conn, 200, serialize_task(task))

      {:error, reason} ->
        json(conn, 422, %{error: inspect(reason)})
    end
  end

  post "/:task_id/pause" do
    company = find_company_for_task(task_id)
    result = if company do
      Shazam.RalphLoop.pause_task(company, task_id)
    else
      Shazam.TaskBoard.pause(task_id)
    end

    case result do
      {:ok, _} ->
        case Shazam.TaskBoard.get(task_id) do
          {:ok, task} -> json(conn, 200, %{task: serialize_task(task)})
          _ -> json(conn, 200, %{task: %{id: task_id, status: "paused"}})
        end
      {:error, reason} -> json(conn, 422, %{error: inspect(reason)})
    end
  end

  post "/:task_id/resume" do
    company = find_company_for_task(task_id)
    result = if company do
      Shazam.RalphLoop.resume_task(company, task_id)
    else
      Shazam.TaskBoard.resume_task(task_id)
    end

    case result do
      {:ok, _} ->
        case Shazam.TaskBoard.get(task_id) do
          {:ok, task} -> json(conn, 200, %{task: serialize_task(task)})
          _ -> json(conn, 200, %{task: %{id: task_id, status: "pending"}})
        end
      {:error, reason} -> json(conn, 422, %{error: inspect(reason)})
    end
  end

  post "/:task_id/reassign" do
    new_agent = conn.body_params["assigned_to"] || ""

    if new_agent == "" do
      json(conn, 400, %{error: "assigned_to is required"})
    else
      case Shazam.TaskBoard.reassign(task_id, new_agent) do
        {:ok, task} ->
          json(conn, 200, %{status: "reassigned", task: serialize_task(task)})

        {:error, reason} ->
          json(conn, 422, %{error: inspect(reason)})
      end
    end
  end

  post "/:task_id/approve-stage" do
    case Shazam.TaskBoard.get(task_id) do
      {:ok, _task} ->
        output = conn.body_params["output"] || "Stage approved manually"
        approved_by = conn.body_params["approved_by"] || "user"
        case Shazam.TaskBoard.advance_stage(task_id, output, approved_by) do
          {:completed, updated} ->
            json(conn, 200, %{status: "completed", task: serialize_task(updated)})
          {:ok, updated} ->
            json(conn, 200, %{status: "advanced", task: serialize_task(updated)})
          {:error, reason} ->
            json(conn, 422, %{error: inspect(reason)})
        end
      _ ->
        json(conn, 404, %{error: "Task not found"})
    end
  end

  post "/:task_id/reject-stage" do
    reason = conn.body_params["reason"] || "Rejected"
    rejected_by = conn.body_params["rejected_by"] || "user"
    case Shazam.TaskBoard.reject_stage(task_id, reason, rejected_by) do
      {:ok, updated} ->
        json(conn, 200, %{status: "rejected", task: serialize_task(updated)})
      {:error, reason} ->
        json(conn, 422, %{error: inspect(reason)})
    end
  end

  post "/:task_id/restore" do
    case Shazam.TaskBoard.restore(task_id) do
      {:ok, _} ->
        Shazam.API.EventBus.broadcast(%{event: "task_restored", task_id: task_id})
        json(conn, 200, %{status: "restored"})

      {:error, reason} ->
        json(conn, 422, %{error: inspect(reason)})
    end
  end

  delete "/:task_id" do
    case Shazam.TaskBoard.delete(task_id) do
      {:ok, _} ->
        Shazam.API.EventBus.broadcast(%{event: "task_deleted", task_id: task_id})
        json(conn, 200, %{status: "deleted"})

      {:error, reason} ->
        json(conn, 422, %{error: inspect(reason)})
    end
  end

  put "/:task_id" do
    updates =
      conn.body_params
      |> Enum.reduce(%{}, fn
        {"title", v}, acc when is_binary(v) -> Map.put(acc, :title, v)
        {"description", v}, acc when is_binary(v) -> Map.put(acc, :description, v)
        {"assigned_to", v}, acc when is_binary(v) -> Map.put(acc, :assigned_to, v)
        _, acc -> acc
      end)

    case Shazam.TaskBoard.update(task_id, updates) do
      {:ok, task} ->
        Shazam.API.EventBus.broadcast(%{event: "task_updated", task: serialize_task(task)})
        json(conn, 200, %{task: serialize_task(task)})

      {:error, :not_found} ->
        json(conn, 404, %{error: "Task not found"})

      {:error, reason} ->
        json(conn, 422, %{error: inspect(reason)})
    end
  end

  match _ do
    json(conn, 404, %{error: "Not found"})
  end

  defp tasks_to_csv(tasks) do
    header = "id,title,status,assigned_to,created_by,company,created_at,updated_at,description\n"

    rows =
      Enum.map_join(tasks, "\n", fn t ->
        [
          t.id,
          escape_csv(t.title),
          to_string(t.status),
          t.assigned_to || "",
          t.created_by || "",
          Map.get(t, :company) || "",
          to_string(t.created_at),
          to_string(t.updated_at),
          escape_csv(t.description || "")
        ]
        |> Enum.join(",")
      end)

    header <> rows
  end

  defp escape_csv(nil), do: ""

  defp escape_csv(text) do
    if String.contains?(text, [",", "\"", "\n"]) do
      "\"" <> String.replace(text, "\"", "\"\"") <> "\""
    else
      text
    end
  end
end
