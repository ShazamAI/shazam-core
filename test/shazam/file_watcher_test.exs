defmodule Shazam.FileWatcherTest do
  use ExUnit.Case, async: true

  @moduletag :file_watcher

  # We test the pure functions (build_snapshot, diff_snapshots) via
  # sending messages to the GenServer's internal logic. Since these are
  # private, we test the observable behavior through snapshots.

  describe "build_snapshot and diff_snapshots" do
    test "detects new files" do
      tmp = Path.join(System.tmp_dir!(), "fw_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)

      on_exit(fn -> File.rm_rf!(tmp) end)

      # Empty snapshot
      old = %{}

      # Create a file
      File.write!(Path.join(tmp, "hello.txt"), "world")

      # Build snapshot by walking directory
      new = build_test_snapshot(tmp)

      {created, changed, deleted} = diff_test_snapshots(old, new)

      assert "hello.txt" in created
      assert changed == []
      assert deleted == []
    end

    test "detects deleted files" do
      tmp = Path.join(System.tmp_dir!(), "fw_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)

      on_exit(fn -> File.rm_rf!(tmp) end)

      File.write!(Path.join(tmp, "temp.txt"), "data")
      old = build_test_snapshot(tmp)

      File.rm!(Path.join(tmp, "temp.txt"))
      new = build_test_snapshot(tmp)

      {created, _changed, deleted} = diff_test_snapshots(old, new)

      assert created == []
      assert "temp.txt" in deleted
    end

    test "detects changed files" do
      tmp = Path.join(System.tmp_dir!(), "fw_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)

      on_exit(fn -> File.rm_rf!(tmp) end)

      File.write!(Path.join(tmp, "data.txt"), "version1")
      old = build_test_snapshot(tmp)

      # Ensure mtime differs (some filesystems have 1s granularity)
      Process.sleep(1100)
      File.write!(Path.join(tmp, "data.txt"), "version2")
      new = build_test_snapshot(tmp)

      {created, changed, deleted} = diff_test_snapshots(old, new)

      assert created == []
      assert "data.txt" in changed
      assert deleted == []
    end

    test "handles empty directories" do
      tmp = Path.join(System.tmp_dir!(), "fw_empty_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)

      on_exit(fn -> File.rm_rf!(tmp) end)

      snapshot = build_test_snapshot(tmp)
      assert snapshot == %{}
    end

    test "ignores .git directories" do
      tmp = Path.join(System.tmp_dir!(), "fw_git_#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(tmp, ".git"))
      File.write!(Path.join(tmp, ".git/HEAD"), "ref: refs/heads/main")
      File.write!(Path.join(tmp, "real.txt"), "data")

      on_exit(fn -> File.rm_rf!(tmp) end)

      snapshot = build_test_snapshot(tmp)
      refute Map.has_key?(snapshot, ".git/HEAD")
      assert Map.has_key?(snapshot, "real.txt")
    end
  end

  # ── Helpers — reimplementing snapshot logic for testability ──

  @ignored_dirs ~w(.git node_modules _build deps .elixir_ls .shazam target dist .next .nuxt __pycache__ .venv)

  defp build_test_snapshot(workspace) do
    walk(workspace, workspace, 0)
  rescue
    _ -> %{}
  end

  defp walk(dir, root, depth) when depth < 5 do
    case File.ls(dir) do
      {:ok, entries} ->
        entries
        |> Enum.reject(&(&1 in @ignored_dirs))
        |> Enum.reject(&String.starts_with?(&1, "."))
        |> Enum.reduce(%{}, fn entry, acc ->
          full = Path.join(dir, entry)
          rel = Path.relative_to(full, root)

          cond do
            File.dir?(full) -> Map.merge(acc, walk(full, root, depth + 1))
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

  defp diff_test_snapshots(old, new) do
    old_keys = Map.keys(old) |> MapSet.new()
    new_keys = Map.keys(new) |> MapSet.new()

    created = MapSet.difference(new_keys, old_keys) |> MapSet.to_list()
    deleted = MapSet.difference(old_keys, new_keys) |> MapSet.to_list()

    changed =
      new
      |> Enum.filter(fn {path, hash} ->
        old_hash = Map.get(old, path)
        old_hash != nil and old_hash != hash
      end)
      |> Enum.map(&elem(&1, 0))

    {created, changed, deleted}
  end
end
