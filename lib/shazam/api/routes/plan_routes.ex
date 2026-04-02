defmodule Shazam.API.Routes.PlanRoutes do
  @moduledoc "REST endpoints for the Plans system."

  use Plug.Router
  require Logger
  import Shazam.API.Helpers

  plug :match
  plug :dispatch

  # GET /plans — list all plans
  get "/" do
    plans = Shazam.PlanManager.list_plans()
    json(conn, 200, %{plans: plans})
  end

  # GET /plans/:plan_id — get a specific plan
  get "/:plan_id" do
    case Shazam.PlanManager.read_plan(plan_id) do
      {:ok, plan} -> json(conn, 200, %{plan: plan})
      {:error, :not_found} -> json(conn, 404, %{error: "Plan not found"})
    end
  end

  # POST /plans — create a new plan (generates prompt, creates PM task)
  # Body: { description: string }
  post "/" do
    description = conn.body_params["description"]

    if !description || description == "" do
      json(conn, 400, %{error: "description is required"})
    else
      plan_id = Shazam.PlanManager.next_id()

      # Save draft plan — NO task created yet.
      # Tasks are only created when the user approves the plan.
      draft_plan = %{
        id: plan_id,
        title: String.slice(description, 0..80),
        status: "draft",
        summary: description,
        created_at: DateTime.to_iso8601(DateTime.utc_now()),
        tasks: [],
        architecture: %{},
        risks: []
      }
      Shazam.PlanManager.ensure_dir()
      Shazam.PlanManager.save_plan(draft_plan)

      json(conn, 201, %{plan_id: plan_id, status: "draft"})
    end
  end

  # POST /plans/:plan_id/approve — approve a draft plan, creating tasks
  post "/:plan_id/approve" do
    company = conn.body_params["company"]

    case Shazam.PlanManager.read_plan(plan_id) do
      {:ok, plan} ->
        case Shazam.PlanManager.create_tasks_from_plan(plan, company) do
          {:ok, count} -> json(conn, 200, %{status: "approved", tasks_created: count})
          {:error, reason} -> json(conn, 500, %{error: inspect(reason)})
        end
      {:error, :not_found} -> json(conn, 404, %{error: "Plan not found"})
    end
  end

  # PUT /plans/:plan_id — update a plan (title, status, tasks)
  put "/:plan_id" do
    case Shazam.PlanManager.read_plan(plan_id) do
      {:ok, plan} ->
        updates = conn.body_params
        updated = plan
        |> maybe_put(:title, updates["title"])
        |> maybe_put(:status, updates["status"])
        |> maybe_put(:tasks, updates["tasks"])
        |> maybe_put(:summary, updates["summary"])
        |> maybe_put(:architecture, updates["architecture"])
        |> maybe_put(:risks, updates["risks"])

        Shazam.PlanManager.save_plan(updated)
        json(conn, 200, %{plan: updated})
      {:error, :not_found} -> json(conn, 404, %{error: "Plan not found"})
    end
  end

  # DELETE /plans/:plan_id
  delete "/:plan_id" do
    workspace = Application.get_env(:shazam, :workspace, File.cwd!())
    path = Path.join([workspace, ".shazam", "plans", "#{plan_id}.md"])
    File.rm(path)
    json(conn, 200, %{status: "ok"})
  end

  # POST /plans/:plan_id/refine — refine plan with AI feedback (no task created)
  # Body: { feedback: string }
  # The feedback is appended to the plan summary for now.
  # In the future, this could call Claude directly to rewrite the plan.
  post "/:plan_id/refine" do
    feedback = conn.body_params["feedback"] || ""

    case Shazam.PlanManager.read_plan(plan_id) do
      {:ok, plan} ->
        # Append feedback to summary
        current_summary = plan[:summary] || ""
        updated_summary = current_summary <> "\n\n---\n**Refinement feedback:**\n" <> feedback

        updated_plan = %{plan | summary: updated_summary}
        Shazam.PlanManager.save_plan(updated_plan)

        json(conn, 200, %{status: "refined", plan_id: plan_id, plan: updated_plan})
      {:error, :not_found} -> json(conn, 404, %{error: "Plan not found"})
    end
  end

  match _ do
    json(conn, 404, %{error: "Not found"})
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
