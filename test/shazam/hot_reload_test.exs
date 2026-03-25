defmodule Shazam.HotReloadTest do
  use ExUnit.Case, async: true

  @moduletag :hot_reload

  describe "reload_module/1" do
    test "reloads a valid module" do
      {status, mod, reason} = Shazam.HotReload.reload_module(Shazam.Store)
      assert status in [:ok, :skipped]
      assert mod == Shazam.Store
      assert is_binary(reason)
    end

    test "returns skipped for non-existent module" do
      {status, mod, _reason} = Shazam.HotReload.reload_module(NonExistentModule12345)
      assert status in [:skipped, :error]
      assert mod == NonExistentModule12345
    end

    test "reloads multiple different modules" do
      modules = [Shazam.Store, Shazam.Hierarchy, Shazam.API.WebSocketCommands.Helpers]

      results = Enum.map(modules, &Shazam.HotReload.reload_module/1)

      Enum.each(results, fn {status, _mod, _reason} ->
        assert status in [:ok, :skipped]
      end)
    end
  end
end
