defmodule Shazam.FileWatcher do
  @moduledoc """
  Watches workspace for file changes via polling.
  Broadcasts file_created, file_changed, file_deleted events via EventBus.
  """

  use GenServer

  @poll_interval 2_000
  @ignored_dirs ~w(.git node_modules _build deps .elixir_ls .shazam target dist .next .nuxt __pycache__ .venv)
  @max_depth 5

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def set_workspace(path) when is_binary(path) do
    GenServer.cast(__MODULE__, {:set_workspace, path})
  end

  def set_workspace(_), do: :ok

  @impl true
  def init(_) do
    workspace = Application.get_env(:shazam, :workspace, nil)
    state = %{workspace: workspace, snapshot: %{}, interval: @poll_interval}

    if workspace && File.dir?(workspace) do
      snapshot = build_snapshot(workspace)
      schedule_poll(state.interval)
      {:ok, %{state | snapshot: snapshot}}
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_cast({:set_workspace, path}, state) do
    if File.dir?(path) do
      snapshot = build_snapshot(path)
      schedule_poll(state.interval)
      {:noreply, %{state | workspace: path, snapshot: snapshot}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:poll, %{workspace: nil} = state), do: {:noreply, state}

  def handle_info(:poll, state) do
    new_snapshot = build_snapshot(state.workspace)
    {created, changed, deleted} = diff_snapshots(state.snapshot, new_snapshot)

    ts = DateTime.to_iso8601(DateTime.utc_now())

    Enum.each(created, fn path ->
      Shazam.API.EventBus.broadcast(%{event: "file_created", path: path, timestamp: ts})
    end)

    Enum.each(changed, fn path ->
      Shazam.API.EventBus.broadcast(%{event: "file_changed", path: path, timestamp: ts})
    end)

    Enum.each(deleted, fn path ->
      Shazam.API.EventBus.broadcast(%{event: "file_deleted", path: path, timestamp: ts})
    end)

    schedule_poll(state.interval)
    {:noreply, %{state | snapshot: new_snapshot}}
  end

  # ── Private ─────────────────────────────────────────

  defp schedule_poll(interval) do
    Process.send_after(self(), :poll, interval)
  end

  defp build_snapshot(workspace) do
    walk(workspace, workspace, 0)
  rescue
    _ -> %{}
  end

  defp walk(dir, root, depth) when depth < @max_depth do
    case File.ls(dir) do
      {:ok, entries} ->
        entries
        |> Enum.reject(&(&1 in @ignored_dirs))
        |> Enum.reject(&String.starts_with?(&1, "."))
        |> Enum.reduce(%{}, fn entry, acc ->
          full = Path.join(dir, entry)
          rel = Path.relative_to(full, root)

          cond do
            File.dir?(full) ->
              Map.merge(acc, walk(full, root, depth + 1))
            File.regular?(full) ->
              case File.stat(full) do
                {:ok, %{mtime: mtime}} -> Map.put(acc, rel, :erlang.phash2(mtime))
                _ -> acc
              end
            true -> acc
          end
        end)
      _ -> %{}
    end
  end

  defp walk(_, _, _), do: %{}

  defp diff_snapshots(old, new) do
    old_keys = Map.keys(old) |> MapSet.new()
    new_keys = Map.keys(new) |> MapSet.new()

    created = MapSet.difference(new_keys, old_keys) |> MapSet.to_list()
    deleted = MapSet.difference(old_keys, new_keys) |> MapSet.to_list()

    changed = new
      |> Enum.filter(fn {path, hash} ->
        old_hash = Map.get(old, path)
        old_hash != nil and old_hash != hash
      end)
      |> Enum.map(&elem(&1, 0))

    {created, changed, deleted}
  end
end
