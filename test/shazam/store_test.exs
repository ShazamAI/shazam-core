defmodule Shazam.StoreTest do
  use ExUnit.Case, async: false

  @moduletag :store

  setup do
    # Use unique keys to avoid conflicts
    test_key = "test_store_#{System.unique_integer([:positive])}"

    on_exit(fn ->
      Shazam.Store.delete(test_key)
    end)

    %{key: test_key}
  end

  describe "data_dir/0" do
    test "returns a path under home directory" do
      dir = Shazam.Store.data_dir()
      assert is_binary(dir)
      assert String.ends_with?(dir, ".shazam")
    end
  end

  describe "save/2 and load/1" do
    test "saves and loads a map", %{key: key} do
      data = %{"name" => "test", "count" => 42, "nested" => %{"a" => 1}}

      assert :ok = Shazam.Store.save(key, data)
      assert {:ok, loaded} = Shazam.Store.load(key)

      assert loaded["name"] == "test"
      assert loaded["count"] == 42
      assert loaded["nested"]["a"] == 1
    end

    test "saves and loads a list", %{key: key} do
      data = [1, 2, 3, "four"]

      assert :ok = Shazam.Store.save(key, data)
      assert {:ok, loaded} = Shazam.Store.load(key)

      assert loaded == [1, 2, 3, "four"]
    end

    test "overwrites existing data", %{key: key} do
      Shazam.Store.save(key, %{"v" => 1})
      Shazam.Store.save(key, %{"v" => 2})

      assert {:ok, loaded} = Shazam.Store.load(key)
      assert loaded["v"] == 2
    end
  end

  describe "load/1 errors" do
    test "returns {:error, :not_found} for missing key" do
      assert {:error, :not_found} = Shazam.Store.load("nonexistent_key_#{System.unique_integer([:positive])}")
    end
  end

  describe "delete/1" do
    test "deletes saved data", %{key: key} do
      Shazam.Store.save(key, %{"data" => true})
      assert {:ok, _} = Shazam.Store.load(key)

      Shazam.Store.delete(key)
      assert {:error, :not_found} = Shazam.Store.load(key)
    end

    test "returns :ok for non-existent key" do
      assert :ok = Shazam.Store.delete("never_existed_#{System.unique_integer([:positive])}")
    end
  end

  describe "list_keys/1" do
    test "lists keys with matching prefix" do
      prefix = "test_list_#{System.unique_integer([:positive])}"
      key1 = "#{prefix}_a"
      key2 = "#{prefix}_b"

      Shazam.Store.save(key1, %{"a" => 1})
      Shazam.Store.save(key2, %{"b" => 2})

      on_exit(fn ->
        Shazam.Store.delete(key1)
        Shazam.Store.delete(key2)
      end)

      keys = Shazam.Store.list_keys(prefix)
      assert key1 in keys
      assert key2 in keys
    end

    test "returns empty list for no matches" do
      keys = Shazam.Store.list_keys("zzz_no_match_prefix_#{System.unique_integer([:positive])}")
      assert keys == []
    end
  end

  describe "init/0" do
    test "creates the data directory" do
      assert :ok = Shazam.Store.init()
      assert File.dir?(Shazam.Store.data_dir())
    end
  end

  describe "key sanitization" do
    test "handles keys with special characters" do
      key = "test:special/chars_#{System.unique_integer([:positive])}"

      on_exit(fn -> Shazam.Store.delete(key) end)

      assert :ok = Shazam.Store.save(key, %{"ok" => true})
      assert {:ok, %{"ok" => true}} = Shazam.Store.load(key)
    end
  end
end
