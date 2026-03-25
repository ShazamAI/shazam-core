defmodule Shazam.API.Routes.ProjectRoutes do
  @moduledoc "REST API for project registry management."

  use Plug.Router

  plug :match
  plug :dispatch

  # GET /api/projects — list all known projects with status
  get "/" do
    projects = Shazam.ProjectRegistry.list()

    json_projects = Enum.map(projects, fn p ->
      %{
        name: p.name,
        path: p.path,
        status: p.status,
        config_file: p.config_file,
        agents_count: p.agents_count,
        last_used: p.last_used,
        registered_at: p.registered_at
      }
    end)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{projects: json_projects}))
  end

  # POST /api/projects — register a new project
  post "/" do
    path = conn.body_params["path"]

    unless path && File.dir?(path) do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(400, Jason.encode!(%{error: "Invalid path or directory not found"}))
    else
      # Auto-detect name from shazam.yaml
      config_file = cond do
        File.exists?(Path.join(path, ".shazam/shazam.yaml")) -> ".shazam/shazam.yaml"
        File.exists?(Path.join(path, "shazam.yaml")) -> "shazam.yaml"
        true -> nil
      end

      name = if config_file do
        case YamlElixir.read_from_file(Path.join(path, config_file)) do
          {:ok, yaml} -> yaml["name"] || yaml["company"] || Path.basename(path)
          _ -> Path.basename(path)
        end
      else
        Path.basename(path)
      end

      agents_count = if config_file do
        case YamlElixir.read_from_file(Path.join(path, config_file)) do
          {:ok, %{"agents" => agents}} when is_map(agents) -> map_size(agents)
          _ -> 0
        end
      else
        0
      end

      Shazam.ProjectRegistry.register(%{
        name: name,
        path: path,
        config_file: config_file,
        agents_count: agents_count
      })

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(201, Jason.encode!(%{ok: true, name: name}))
    end
  end

  # POST /api/projects/:name/start — start a registered project
  post "/:name/start" do
    case Shazam.ProjectRegistry.start_project(name) do
      {:ok, company_name} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{ok: true, company: company_name}))

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(422, Jason.encode!(%{error: to_string(reason)}))
    end
  end

  # POST /api/projects/:name/stop — stop a running project
  post "/:name/stop" do
    Shazam.ProjectRegistry.stop_project(name)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{ok: true}))
  end

  # DELETE /api/projects/:name — remove from registry
  delete "/:name" do
    Shazam.ProjectRegistry.remove(name)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{ok: true}))
  end

  match _ do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{error: "Not found"}))
  end
end
