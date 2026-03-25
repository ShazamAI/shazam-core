defmodule Shazam.Workflow do
  @moduledoc """
  Workflow pipeline engine.

  Workflows define a sequence of stages that a task passes through.
  Each stage has a role requirement and optional configuration.

  Workflows are loaded from `.shazam/workflows/*.yml` in the workspace,
  or fall back to built-in defaults.

  Resolution order (most specific wins):
    1. Task-level `workflow` field (explicit override)
    2. Task template's `workflow` field
    3. Domain-level `workflow` field
    4. Company default_workflow config
    5. "default" (single stage, backwards-compatible)
  """

  require Logger

  @type stage :: %{
          name: String.t(),
          role: String.t(),
          prompt_suffix: String.t() | nil,
          on_reject: String.t() | nil
        }

  @type workflow :: %{
          name: String.t(),
          stages: [stage()]
        }

  @type pipeline_stage :: %{
          name: String.t(),
          role: String.t(),
          status: :pending | :in_progress | :completed | :rejected,
          assigned_to: String.t() | nil,
          completed_by: String.t() | nil,
          output: String.t() | nil,
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil
        }

  # ── Built-in workflows ──────────────────────────────────

  @default_workflow %{
    name: "default",
    stages: [
      %{name: "execute", role: "*", prompt_suffix: nil, on_reject: nil}
    ]
  }

  @builtin_workflows %{
    "default" => @default_workflow,
    "feature" => %{
      name: "feature",
      stages: [
        %{name: "develop", role: "dev", prompt_suffix: "Implement the feature. Do NOT commit yet.", on_reject: nil},
        %{name: "review", role: "reviewer", prompt_suffix: "Review the code changes. Check for bugs, style, security issues. If issues found, reject with details.", on_reject: "develop"},
        %{name: "qa", role: "qa", prompt_suffix: "Test the changes. Run the test suite. Verify functionality manually if needed. If tests fail, reject with details.", on_reject: "develop"},
        %{name: "commit", role: "dev", prompt_suffix: "All reviews and tests passed. Create a clean commit with a descriptive message and push.", on_reject: nil}
      ]
    },
    "hotfix" => %{
      name: "hotfix",
      stages: [
        %{name: "develop", role: "dev", prompt_suffix: "Fix the bug. Do NOT commit yet.", on_reject: nil},
        %{name: "qa", role: "qa", prompt_suffix: "Test the fix. Run relevant tests. Verify the bug is resolved.", on_reject: "develop"},
        %{name: "commit", role: "dev", prompt_suffix: "Fix verified. Commit and push.", on_reject: nil}
      ]
    },
    "review-only" => %{
      name: "review-only",
      stages: [
        %{name: "develop", role: "dev", prompt_suffix: "Implement the changes. Do NOT commit yet.", on_reject: nil},
        %{name: "review", role: "reviewer", prompt_suffix: "Review the code changes thoroughly.", on_reject: "develop"},
        %{name: "commit", role: "dev", prompt_suffix: "Review passed. Commit and push.", on_reject: nil}
      ]
    },
    "docs" => %{
      name: "docs",
      stages: [
        %{name: "write", role: "dev", prompt_suffix: "Write or update the documentation.", on_reject: nil},
        %{name: "review", role: "reviewer", prompt_suffix: "Review documentation for accuracy and clarity.", on_reject: "write"},
        %{name: "commit", role: "dev", prompt_suffix: "Documentation approved. Commit and push.", on_reject: nil}
      ]
    }
  }

  # ── Public API ──────────────────────────────────────────

  @doc "Returns the default single-stage workflow."
  def default_workflow, do: @default_workflow

  @doc "Lists all available workflows (built-in + workspace custom)."
  def list_all(workspace \\ nil) do
    custom = load_custom_workflows(workspace)
    Map.merge(@builtin_workflows, custom)
    |> Map.values()
    |> Enum.sort_by(& &1.name)
  end

  @doc "Gets a workflow by name. Checks workspace custom first, then built-in."
  def get(name, workspace \\ nil) do
    custom = load_custom_workflows(workspace)
    Map.get(custom, name) || Map.get(@builtin_workflows, name)
  end

  @doc """
  Resolves which workflow to use for a task.

  Resolution: task.workflow > template > domain > company default > "default"
  """
  def resolve(task, company_config \\ %{}) do
    workflow_name =
      Map.get(task, :workflow) ||
      Map.get(task, "workflow") ||
      resolve_from_template(task) ||
      resolve_from_domain(task, company_config) ||
      Map.get(company_config, :default_workflow) ||
      Map.get(company_config, "default_workflow") ||
      "default"

    workspace = Application.get_env(:shazam, :workspace, nil)
    get(workflow_name, workspace) || @default_workflow
  end

  @doc "Instantiates a pipeline from a workflow definition."
  def instantiate_pipeline(workflow) do
    workflow.stages
    |> Enum.map(fn stage ->
      %{
        name: stage.name,
        role: stage.role,
        status: :pending,
        assigned_to: nil,
        completed_by: nil,
        output: nil,
        started_at: nil,
        completed_at: nil
      }
    end)
  end

  @doc "Returns the next stage index after the current one, or nil if last."
  def next_stage(pipeline, current_index) do
    if current_index + 1 < length(pipeline) do
      current_index + 1
    else
      nil
    end
  end

  @doc "Returns the stage index to go back to on rejection."
  def reject_target(workflow, current_index) do
    stage_def = Enum.at(workflow.stages, current_index)
    target_name = stage_def && stage_def.on_reject

    if target_name do
      Enum.find_index(workflow.stages, fn s -> s.name == target_name end) || 0
    else
      # Default: go back to first stage
      0
    end
  end

  @doc "Gets the prompt suffix for a specific stage."
  def stage_prompt_suffix(workflow, stage_index) do
    case Enum.at(workflow.stages, stage_index) do
      nil -> nil
      stage -> stage.prompt_suffix
    end
  end

  @doc "Gets the required role for a specific pipeline stage."
  def stage_role(pipeline, stage_index) do
    case Enum.at(pipeline, stage_index) do
      nil -> "*"
      stage -> stage.role
    end
  end

  @doc "Checks if a pipeline has more than one stage (is a real workflow)."
  def has_pipeline?(task) do
    pipeline = Map.get(task, :pipeline) || Map.get(task, "pipeline")
    is_list(pipeline) and length(pipeline) > 1
  end

  @doc "Updates a pipeline stage in-place."
  def update_pipeline_stage(pipeline, index, updates) do
    List.update_at(pipeline, index, fn stage ->
      Map.merge(stage, updates)
    end)
  end

  @doc "Builds stage context string from completed stages for prompt injection."
  def build_stage_context(pipeline, current_index) do
    pipeline
    |> Enum.take(current_index)
    |> Enum.filter(fn s -> s.output && s.output != "" end)
    |> Enum.map(fn s ->
      completed_by = s.completed_by || "unknown"
      """
      ## Stage: #{s.name} (completed by #{completed_by})
      #{s.output}
      """
    end)
    |> Enum.join("\n")
  end

  # ── Private ─────────────────────────────────────────────

  defp load_custom_workflows(nil) do
    workspace = Application.get_env(:shazam, :workspace, nil)
    load_custom_workflows(workspace)
  end

  defp load_custom_workflows(workspace) when is_binary(workspace) do
    dir = Path.join(workspace, ".shazam/workflows")

    if File.dir?(dir) do
      dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".yml"))
      |> Enum.reduce(%{}, fn filename, acc ->
        path = Path.join(dir, filename)
        case parse_workflow_file(path) do
          {:ok, workflow} -> Map.put(acc, workflow.name, workflow)
          _ -> acc
        end
      end)
    else
      %{}
    end
  rescue
    _ -> %{}
  end

  defp load_custom_workflows(_), do: %{}

  defp parse_workflow_file(path) do
    case File.read(path) do
      {:ok, content} ->
        case YamlElixir.read_from_string(content) do
          {:ok, data} when is_map(data) ->
            name = data["name"] || Path.basename(path, ".yml")
            raw_stages = data["stages"] || []

            stages = Enum.map(raw_stages, fn s ->
              %{
                name: s["name"] || "unnamed",
                role: s["role"] || "*",
                prompt_suffix: s["prompt_suffix"],
                on_reject: s["on_reject"]
              }
            end)

            if length(stages) > 0 do
              {:ok, %{name: name, stages: stages}}
            else
              {:error, :no_stages}
            end

          _ -> {:error, :invalid_yaml}
        end

      {:error, reason} -> {:error, reason}
    end
  rescue
    _ -> {:error, :parse_error}
  end

  defp resolve_from_template(task) do
    template_id = Map.get(task, :template) || Map.get(task, "template")
    if template_id do
      case Shazam.TaskTemplates.get(template_id) do
        nil -> nil
        template -> Map.get(template, :workflow) || Map.get(template, "workflow")
      end
    end
  rescue
    _ -> nil
  end

  defp resolve_from_domain(task, company_config) do
    domain = Map.get(task, :domain) || Map.get(task, "domain")
    if domain do
      domain_config = get_in(company_config, [:domain_config, domain]) ||
                      get_in(company_config, ["domain_config", domain]) || %{}
      Map.get(domain_config, :workflow) || Map.get(domain_config, "workflow")
    end
  rescue
    _ -> nil
  end
end
