defmodule Shazam.ProjectRegistry do
  @moduledoc """
  Persistent registry of known Shazam projects.
  Stores project metadata in ~/.shazam/projects.json.
  Projects are auto-registered when TUI connects, or manually via API.
  """

  use GenServer

  @registry_file "projects.json"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  # ── Public API ──────────────────────────────────────

  @doc "List all known projects with their running status."
  def list do
    GenServer.call(__MODULE__, :list)
  end

  @doc "Get a single project by name."
  def get(name) do
    GenServer.call(__MODULE__, {:get, name})
  end

  @doc "Register a project (upsert by path)."
  def register(attrs) do
    GenServer.call(__MODULE__, {:register, attrs})
  end

  @doc "Remove a project from the registry."
  def remove(name) do
    GenServer.call(__MODULE__, {:remove, name})
  end

  @doc "Start a project: read its shazam.yaml, start company + agents."
  def start_project(name) do
    GenServer.call(__MODULE__, {:start_project, name}, 30_000)
  end

  @doc "Stop a running project."
  def stop_project(name) do
    GenServer.call(__MODULE__, {:stop_project, name})
  end

  # ── GenServer ───────────────────────────────────────

  @impl true
  def init(_) do
    projects = load_from_disk()
    {:ok, %{projects: projects}}
  end

  @impl true
  def handle_call(:list, _from, state) do
    enriched = Enum.map(state.projects, &enrich_status/1)
    {:reply, enriched, state}
  end

  def handle_call({:get, name}, _from, state) do
    case Enum.find(state.projects, &(&1.name == name)) do
      nil -> {:reply, {:error, :not_found}, state}
      project -> {:reply, {:ok, enrich_status(project)}, state}
    end
  end

  def handle_call({:register, attrs}, _from, state) do
    name = attrs[:name] || attrs["name"]
    path = attrs[:path] || attrs["path"]
    config_file = attrs[:config_file] || attrs["config_file"] || find_config_file(path)
    agents_count = attrs[:agents_count] || attrs["agents_count"] || 0

    # Ensure name is a string (not a map from nested YAML)
    name = cond do
      is_binary(name) -> name
      is_map(name) && is_binary(name["name"]) -> name["name"]
      true -> Path.basename(to_string(path))
    end

    project = %{
      name: name,
      path: path,
      config_file: config_file,
      agents_count: agents_count,
      last_used: DateTime.to_iso8601(DateTime.utc_now()),
      registered_at: nil
    }

    # Upsert by path
    projects = state.projects
      |> Enum.reject(&(&1.path == path))
      |> List.insert_at(0, %{project | registered_at: find_registered_at(state.projects, path)})

    # Set registered_at if new
    projects = Enum.map(projects, fn p ->
      if p.registered_at == nil, do: %{p | registered_at: project.last_used}, else: p
    end)

    save_to_disk(projects)
    {:reply, :ok, %{state | projects: projects}}
  end

  def handle_call({:remove, name}, _from, state) do
    projects = Enum.reject(state.projects, &(&1.name == name))
    save_to_disk(projects)
    {:reply, :ok, %{state | projects: projects}}
  end

  def handle_call({:start_project, name}, _from, state) do
    case Enum.find(state.projects, &(&1.name == name)) do
      nil ->
        {:reply, {:error, :not_found}, state}

      project ->
        result = do_start_project(project)

        # Update last_used
        projects = Enum.map(state.projects, fn p ->
          if p.name == name, do: %{p | last_used: DateTime.to_iso8601(DateTime.utc_now())}, else: p
        end)
        save_to_disk(projects)

        {:reply, result, %{state | projects: projects}}
    end
  end

  def handle_call({:stop_project, name}, _from, state) do
    result = try do
      if Shazam.RalphLoop.exists?(name) do
        Shazam.RalphLoop.pause(name)
      end
      # Stop the company
      case Registry.lookup(Shazam.CompanyRegistry, name) do
        [{pid, _}] ->
          DynamicSupervisor.terminate_child(Shazam.CompanySupervisor, pid)
          :ok
        _ -> :ok
      end
    catch
      _, _ -> :ok
    end
    {:reply, result, state}
  end

  # ── Private ─────────────────────────────────────────

  defp do_start_project(project) do
    path = project.path
    config_file = project.config_file || find_config_file(path)
    full_config_path = Path.join(path, config_file)

    unless File.exists?(full_config_path) do
      {:error, "Config file not found: #{full_config_path}"}
    else
      # Parse the YAML config
      case YamlElixir.read_from_file(full_config_path) do
        {:ok, yaml} ->
          # Support both flat (name: X) and nested (company: {name: X}) formats
          company_name = cond do
            is_binary(yaml["name"]) -> yaml["name"]
            is_map(yaml["company"]) && is_binary(yaml["company"]["name"]) -> yaml["company"]["name"]
            is_binary(project.name) -> project.name
            true -> Path.basename(path)
          end
          agents = parse_agents(yaml["agents"] || %{})
          mission = cond do
            is_binary(yaml["mission"]) -> yaml["mission"]
            is_map(yaml["company"]) && is_binary(yaml["company"]["mission"]) -> yaml["company"]["mission"]
            true -> ""
          end

          # Set workspace
          Application.put_env(:shazam, :workspace, path)

          company_config = %{
            name: company_name,
            mission: mission,
            agents: agents,
            domain_config: yaml["domains"] || %{}
          }

          # Start company
          case Shazam.start_company(company_config) do
            {:ok, _} ->
              # Wait for RalphLoop and resume
              wait_for_ralph(company_name, 15)
              if Shazam.RalphLoop.exists?(company_name) do
                Shazam.RalphLoop.resume(company_name)
              end
              {:ok, company_name}

            {:error, {:already_started, _}} ->
              if Shazam.RalphLoop.exists?(company_name) do
                Shazam.RalphLoop.resume(company_name)
              end
              {:ok, company_name}

            {:error, reason} ->
              {:error, inspect(reason)}
          end

        {:error, reason} ->
          {:error, "Failed to parse YAML: #{inspect(reason)}"}
      end
    end
  rescue
    e -> {:error, inspect(e)}
  end

  defp parse_agents(agents_map) when is_map(agents_map) do
    Enum.map(agents_map, fn {name, config} ->
      config = if is_map(config), do: config, else: %{}
      %{
        name: to_string(name),
        role: config["role"] || "Senior Developer",
        supervisor: config["supervisor"],
        workspace: config["workspace"],
        provider: config["provider"],
        budget: config["budget"],
        domain: config["domain"]
      }
    end)
  end
  defp parse_agents(_), do: []

  defp wait_for_ralph(company, retries) when retries > 0 do
    if Shazam.RalphLoop.exists?(company), do: :ok,
    else: (Process.sleep(500); wait_for_ralph(company, retries - 1))
  end
  defp wait_for_ralph(_, _), do: :ok

  defp enrich_status(project) do
    running = try do
      case Registry.lookup(Shazam.CompanyRegistry, project.name) do
        [{_, _}] -> true
        _ -> false
      end
    catch
      _, _ -> false
    end

    Map.put(project, :status, if(running, do: "running", else: "stopped"))
  end

  defp find_registered_at(projects, path) do
    case Enum.find(projects, &(&1.path == path)) do
      %{registered_at: at} -> at
      _ -> nil
    end
  end

  defp find_config_file(path) when is_binary(path) do
    cond do
      File.exists?(Path.join(path, ".shazam/shazam.yaml")) -> ".shazam/shazam.yaml"
      File.exists?(Path.join(path, "shazam.yaml")) -> "shazam.yaml"
      true -> "shazam.yaml"
    end
  end
  defp find_config_file(_), do: "shazam.yaml"

  defp registry_path do
    Path.join(Shazam.Store.data_dir(), @registry_file)
  end

  defp load_from_disk do
    case File.read(registry_path()) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, list} when is_list(list) ->
            Enum.map(list, fn item ->
              %{
                name: item["name"] || "",
                path: item["path"] || "",
                config_file: item["config_file"] || "shazam.yaml",
                agents_count: item["agents_count"] || 0,
                last_used: item["last_used"],
                registered_at: item["registered_at"]
              }
            end)
          _ -> []
        end
      _ -> []
    end
  end

  defp save_to_disk(projects) do
    data = Enum.map(projects, fn p ->
      %{
        name: p.name,
        path: p.path,
        config_file: p.config_file,
        agents_count: p.agents_count,
        last_used: p.last_used,
        registered_at: p.registered_at
      }
    end)
    File.mkdir_p!(Path.dirname(registry_path()))
    File.write!(registry_path(), Jason.encode!(data, pretty: true))
  end
end
