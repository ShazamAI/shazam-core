defmodule Shazam.API.Routes.PlanRoutes do
  @moduledoc "REST endpoints for the Plans system."

  use Plug.Router
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
  # Body: { description: string, company: string }
  post "/" do
    description = conn.body_params["description"]
    company = conn.body_params["company"]

    if !description || description == "" do
      json(conn, 400, %{error: "description is required"})
    else
      plan_id = Shazam.PlanManager.next_id()
      prompt = Shazam.PlanManager.build_plan_prompt(description)

      # Find PM agent
      pm_name = try do
        agents = Shazam.Company.get_agents(company)
        case Enum.find(agents, fn a -> a.supervisor == nil and String.contains?(String.downcase(a.role), "manager") end) do
          nil -> "pm"
          agent -> agent.name
        end
      catch
        _, _ -> "pm"
      end

      # Save an initial draft plan file so it appears in the list immediately
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

      # Create planning task for PM
      case Shazam.TaskBoard.create(%{
        title: "Create plan: #{String.slice(description, 0..80)}",
        assigned_to: pm_name,
        created_by: "human",
        company: company,
        description: prompt <> "\n\nPlan ID: #{plan_id}"
      }) do
        {:ok, task} -> json(conn, 201, %{plan_id: plan_id, task_id: task.id, status: "draft"})
        {:error, reason} -> json(conn, 500, %{error: inspect(reason)})
      end
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

  # POST /plans/:plan_id/refine — ask AI to refine the plan
  post "/:plan_id/refine" do
    company = conn.body_params["company"]
    feedback = conn.body_params["feedback"] || ""

    case Shazam.PlanManager.read_plan(plan_id) do
      {:ok, plan} ->
        # Find PM
        pm_name = try do
          agents = Shazam.Company.get_agents(company)
          case Enum.find(agents, fn a -> a.supervisor == nil and String.contains?(String.downcase(a.role), "manager") end) do
            nil -> "pm"
            agent -> agent.name
          end
        catch
          _, _ -> "pm"
        end

        # Create refinement task
        refine_prompt = """
        Review and refine this existing plan:

        Title: #{plan.title}
        Summary: #{plan[:summary] || ""}

        Current tasks:
        #{Enum.map_join(plan[:tasks] || [], "\n", fn t -> "- #{t[:title]} → #{t[:assigned_to]}" end)}

        User feedback for refinement:
        #{feedback}

        Output the complete refined plan in the same JSON format (title, summary, architecture, phases, risks).
        Keep the same Plan ID: #{plan_id}
        """

        case Shazam.TaskBoard.create(%{
          title: "Refine plan: #{plan.title}",
          assigned_to: pm_name,
          created_by: "human",
          company: company,
          description: refine_prompt
        }) do
          {:ok, task} -> json(conn, 200, %{status: "refining", task_id: task.id, plan_id: plan_id})
          {:error, reason} -> json(conn, 500, %{error: inspect(reason)})
        end
      {:error, :not_found} -> json(conn, 404, %{error: "Plan not found"})
    end
  end

  match _ do
    json(conn, 404, %{error: "Not found"})
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
