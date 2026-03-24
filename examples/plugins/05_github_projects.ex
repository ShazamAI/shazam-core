defmodule ShazamPlugin.GitHubProjects do
  @moduledoc """
  Loads tasks from GitHub Organization Projects and syncs completion back.
  Uses `gh project item-list` to read from org-level Project boards.
  """

  use Shazam.Plugin

  defp log_path do
    workspace = Application.get_env(:shazam, :workspace, File.cwd!())
    Path.join([workspace, ".shazam", "logs", "plugin.log"])
  end

  @impl true
  def on_init(ctx) do
    config = ctx.plugin_config
    org = config["org"] || "ShazamAI"
    project_number = config["project_number"] || 1
    import_statuses = config["import_statuses"] || ["Ready"]

    log("GitHubProjects: Loading from #{org} project ##{project_number} (statuses: #{Enum.join(import_statuses, ", ")})...")

    case run_gh(["project", "item-list", to_string(project_number),
      "--owner", org, "--format", "json"
    ]) do
      {:ok, %{"items" => items}} when is_list(items) ->
        # Only import items with matching status
        actionable = Enum.filter(items, fn item ->
          status = item["status"] || ""
          status in import_statuses
        end)

        log("GitHubProjects: Found #{length(items)} total, #{length(actionable)} ready to import")

        imported = Enum.reduce(actionable, 0, fn item, count ->
          title = item["title"] || ""
          content = item["content"] || %{}
          number = content["number"]
          repo = item["repository"] || ""
          body = content["body"] || ""
          status = item["status"] || ""
          labels = item["labels"] || []

          # Build identifier
          id_tag = if number, do: "[GH##{number}]", else: "[P##{item["id"] |> to_string() |> String.slice(-6..-1)}]"

          # Check if already imported
          already_exists = try do
            Shazam.TaskBoard.list()
            |> Enum.any?(fn t -> String.contains?(t.title || "", id_tag) end)
          catch
            _, _ -> false
          end

          unless already_exists do
            # Always assign to manager — he delegates to the right PM
            assigned_to = config["assigned_to"] || "manager"

            # Include repo context in description
            desc = if repo != "" do
              "**Repository:** #{repo}\n**Status:** #{status}\n\n#{body}"
            else
              "**Status:** #{status}\n\n#{body}"
            end

            try do
              Shazam.TaskBoard.create(%{
                title: "#{id_tag} #{title}",
                description: desc,
                assigned_to: assigned_to,
                created_by: "github",
                company: ctx.company_name
              })
              log("GitHubProjects: ✓ #{id_tag} #{title} → #{assigned_to}")
              count + 1
            catch
              _, _ ->
                log("GitHubProjects: ✗ Failed to import #{id_tag}")
                count
            end
          else
            count
          end
        end)

        log("GitHubProjects: Done — #{imported} new task(s) imported")

      {:ok, %{"items" => []}} ->
        log("GitHubProjects: No items in project")

      {:error, reason} ->
        log("GitHubProjects: ✗ Error: #{inspect(reason)}")
    end

    :ok
  end

  @impl true
  def after_task_complete(task_id, result, ctx) do
    config = ctx.plugin_config

    task = try do
      case Shazam.TaskBoard.get(task_id) do
        {:ok, t} -> t
        _ -> nil
      end
    catch
      _, _ -> nil
    end

    if task do
      # If it's a GitHub Issue (has GH# in title), close it
      case Regex.run(~r/\[GH#(\d+)\]/, task.title || "") do
        [_, issue_number] ->
          # Find which repo this issue belongs to
          repo = extract_repo_from_description(task.description)
          if repo do
            preview = result |> to_string() |> String.slice(0..500)
            case System.cmd("gh", [
              "issue", "close", issue_number,
              "--repo", repo,
              "--comment", "**Completed by Shazam** (agent: #{task.assigned_to})\n\n```\n#{preview}\n```"
            ], stderr_to_stdout: true) do
              {_, 0} -> log("GitHubProjects: ✓ Closed #{repo}##{issue_number}")
              {err, _} -> log("GitHubProjects: ✗ Close failed: #{String.slice(err, 0..100)}")
            end
          end
        _ -> :ok
      end
    end

    {:ok, result}
  end

  # ── Helpers ───────────────────────────────────────

  defp extract_repo_from_description(nil), do: nil
  defp extract_repo_from_description(desc) do
    case Regex.run(~r/\*\*Repository:\*\*\s*(.+)/, desc) do
      [_, repo] -> String.trim(repo)
      _ -> nil
    end
  end

  defp run_gh(args) do
    case System.cmd("gh", args, stderr_to_stdout: true) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, data} -> {:ok, data}
          _ ->
            log("GitHubProjects: ✗ JSON parse failed")
            {:error, :parse_failed}
        end
      {error, code} ->
        log("GitHubProjects: ✗ gh exit #{code}: #{String.slice(error, 0..150)}")
        {:error, :gh_failed}
    end
  rescue
    _ -> {:error, :gh_not_available}
  end

  defp log(message) do
    path = log_path()
    File.mkdir_p!(Path.dirname(path))
    File.write(path, "#{message}\n", [:append])
  rescue
    _ -> :ok
  end
end
