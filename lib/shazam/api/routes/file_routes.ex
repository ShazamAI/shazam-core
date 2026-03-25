defmodule Shazam.API.Routes.FileRoutes do
  @moduledoc "REST API for file operations — read, write, tree listing."

  use Plug.Router

  @ignored_dirs ~w(.git node_modules _build deps .elixir_ls .shazam target dist .next .nuxt __pycache__ .venv)
  @max_file_size 1_048_576  # 1MB

  plug :match
  plug :dispatch

  # GET /api/files/tree?path=&depth=3 — directory tree
  get "/tree" do
    workspace = Application.get_env(:shazam, :workspace, nil)

    unless workspace do
      json(conn, 400, %{error: "No workspace set"})
    else
      rel_path = conn.query_params["path"] || ""
      max_depth = String.to_integer(conn.query_params["depth"] || "3")
      full_path = Path.join(workspace, rel_path)

      unless safe_path?(full_path, workspace) do
        json(conn, 403, %{error: "Path outside workspace"})
      else
        tree = build_tree(full_path, workspace, 0, max_depth)
        json(conn, 200, %{tree: tree, path: rel_path, workspace: workspace})
      end
    end
  end

  # GET /api/files?path=... — read file content
  get "/" do
    workspace = Application.get_env(:shazam, :workspace, nil)
    rel_path = conn.query_params["path"] || ""

    unless workspace do
      json(conn, 400, %{error: "No workspace set"})
    else
      full_path = Path.join(workspace, rel_path)

      cond do
        !safe_path?(full_path, workspace) ->
          json(conn, 403, %{error: "Path outside workspace"})

        !File.regular?(full_path) ->
          json(conn, 404, %{error: "File not found"})

        true ->
          case File.stat(full_path) do
            {:ok, %{size: size}} when size > @max_file_size ->
              json(conn, 413, %{error: "File too large (max 1MB)"})

            {:ok, stat} ->
              case File.read(full_path) do
                {:ok, content} ->
                  if binary?(content) do
                    json(conn, 422, %{error: "Binary file — cannot display"})
                  else
                    json(conn, 200, %{
                      path: rel_path,
                      content: content,
                      size: stat.size,
                      extension: Path.extname(rel_path)
                    })
                  end
                {:error, reason} ->
                  json(conn, 500, %{error: "Read failed: #{reason}"})
              end

            _ ->
              json(conn, 500, %{error: "Cannot stat file"})
          end
      end
    end
  end

  # PUT /api/files — write file content
  put "/" do
    workspace = Application.get_env(:shazam, :workspace, nil)
    rel_path = conn.body_params["path"]
    content = conn.body_params["content"]

    cond do
      !workspace ->
        json(conn, 400, %{error: "No workspace set"})

      !rel_path || !content ->
        json(conn, 400, %{error: "Missing path or content"})

      true ->
        full_path = Path.join(workspace, rel_path)

        unless safe_path?(full_path, workspace) do
          json(conn, 403, %{error: "Path outside workspace"})
        else
          File.mkdir_p!(Path.dirname(full_path))
          case File.write(full_path, content) do
            :ok ->
              Shazam.API.EventBus.broadcast(%{
                event: "file_changed",
                path: rel_path,
                timestamp: DateTime.to_iso8601(DateTime.utc_now())
              })
              json(conn, 200, %{ok: true, path: rel_path})

            {:error, reason} ->
              json(conn, 500, %{error: "Write failed: #{reason}"})
          end
        end
    end
  end

  match _ do
    json(conn, 404, %{error: "Not found"})
  end

  # ── Helpers ─────────────────────────────────────────

  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end

  defp safe_path?(full_path, workspace) do
    expanded = Path.expand(full_path)
    ws_expanded = Path.expand(workspace)
    String.starts_with?(expanded, ws_expanded)
  end

  defp binary?(content) do
    # Check first 8KB for null bytes
    content
    |> :binary.part(0, min(byte_size(content), 8192))
    |> :binary.match(<<0>>)
    |> case do
      :nomatch -> false
      _ -> true
    end
  end

  defp build_tree(dir, root, depth, max_depth) when depth < max_depth do
    case File.ls(dir) do
      {:ok, entries} ->
        entries
        |> Enum.reject(&(&1 in @ignored_dirs))
        |> Enum.reject(&String.starts_with?(&1, "."))
        |> Enum.sort()
        |> Enum.map(fn entry ->
          full = Path.join(dir, entry)
          rel = Path.relative_to(full, root)

          if File.dir?(full) do
            children = build_tree(full, root, depth + 1, max_depth)
            %{name: entry, path: rel, type: "directory", children: children}
          else
            stat = case File.stat(full) do
              {:ok, s} -> s
              _ -> %{size: 0}
            end
            %{
              name: entry,
              path: rel,
              type: "file",
              size: Map.get(stat, :size, 0),
              extension: Path.extname(entry),
              children: []
            }
          end
        end)
        # Directories first, then files
        |> Enum.sort_by(fn node -> {if(node.type == "directory", do: 0, else: 1), node.name} end)

      _ -> []
    end
  end

  defp build_tree(_, _, _, _), do: []
end
