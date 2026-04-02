defmodule Shazam.YamlWriter do
  @moduledoc """
  Writes specific sections to shazam.yaml without destroying existing content.
  Preserves comments and formatting of untouched sections.
  """

  require Logger

  @doc """
  Update both the `subagents:` section and per-agent subagent assignments in shazam.yaml.
  Reads the YAML, modifies in memory, writes back.
  """
  def update_subagents(workspace, subagents_config) do
    yaml_path = find_yaml_path(workspace)
    unless yaml_path do
      {:error, :yaml_not_found}
    else
      case YamlElixir.read_from_file(yaml_path) do
        {:ok, config} ->
          # Update global subagents section
          updated = if is_list(subagents_config) && length(subagents_config) > 0 do
            sa_map = Enum.reduce(subagents_config, %{}, fn sa, acc ->
              name = sa["name"] || sa[:name] || ""
              entry = %{"enabled" => true, "model" => sa["model"] || sa[:model] || "sonnet"}
              entry = if sa["readonly"] || sa[:readonly], do: Map.put(entry, "readonly", true), else: entry
              entry = if sa["description"] || sa[:description], do: Map.put(entry, "description", sa["description"] || sa[:description]), else: entry
              Map.put(acc, name, entry)
            end)
            Map.put(config, "subagents", sa_map)
          else
            Map.delete(config, "subagents")
          end

          write_yaml(yaml_path, updated)
          {:ok, yaml_path}

        _ ->
          {:error, :parse_failed}
      end
    end
  end

  @doc """
  Update per-agent subagent assignments in shazam.yaml.
  """
  def update_agent_subagents(workspace, agent_assignments) do
    yaml_path = find_yaml_path(workspace)
    unless yaml_path do
      {:error, :yaml_not_found}
    else
      case YamlElixir.read_from_file(yaml_path) do
        {:ok, config} ->
          agents = config["agents"] || %{}

          updated_agents = Enum.reduce(agent_assignments, agents, fn {agent_name, subs}, acc ->
            case Map.get(acc, agent_name) do
              nil -> acc
              agent_config when is_map(agent_config) ->
                if is_list(subs) && length(subs) > 0 do
                  Map.put(acc, agent_name, Map.put(agent_config, "subagents", subs))
                else
                  Map.put(acc, agent_name, Map.delete(agent_config, "subagents"))
                end
              _ -> acc
            end
          end)

          updated = Map.put(config, "agents", updated_agents)
          write_yaml(yaml_path, updated)
          {:ok, yaml_path}

        _ ->
          {:error, :parse_failed}
      end
    end
  end

  # Write a map back as YAML
  defp write_yaml(path, config) do
    yaml = map_to_yaml(config, 0)
    File.write!(path, yaml)
  end

  defp map_to_yaml(map, indent) when is_map(map) do
    prefix = String.duplicate("  ", indent)
    Enum.map_join(map, "\n", fn {key, value} ->
      cond do
        is_map(value) && map_size(value) > 0 ->
          "#{prefix}#{key}:\n#{map_to_yaml(value, indent + 1)}"
        is_list(value) ->
          if Enum.all?(value, &is_binary/1) || Enum.all?(value, &is_atom/1) do
            # Inline list: [a, b, c]
            items = Enum.map_join(value, ", ", &to_string/1)
            "#{prefix}#{key}: [#{items}]"
          else
            # Block list
            items = Enum.map_join(value, "\n", fn item ->
              if is_map(item) do
                inner = map_to_yaml(item, indent + 2) |> String.trim_leading()
                "#{prefix}  - #{inner}"
              else
                "#{prefix}  - #{item}"
              end
            end)
            "#{prefix}#{key}:\n#{items}"
          end
        is_binary(value) && String.contains?(value, "\n") ->
          "#{prefix}#{key}: |\n#{prefix}  #{String.replace(value, "\n", "\n#{prefix}  ")}"
        is_nil(value) ->
          ""
        true ->
          "#{prefix}#{key}: #{value}"
      end
    end)
    |> String.replace(~r/\n\n+/, "\n")
  end

  # Find the shazam.yaml path
  defp find_yaml_path(workspace) do
    paths = [
      Path.join(workspace, ".shazam/shazam.yaml"),
      Path.join(workspace, "shazam.yaml"),
    ]
    Enum.find(paths, &File.exists?/1)
  end

end
