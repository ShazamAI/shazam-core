defmodule Shazam.ModelProxyTest do
  use ExUnit.Case, async: true

  alias Shazam.ModelProxy

  describe "resolve/2" do
    test "resolves claude opus" do
      assert ModelProxy.resolve("claude", "opus") == "claude-opus-4-6"
    end

    test "resolves claude sonnet" do
      assert ModelProxy.resolve("claude", "sonnet") == "claude-sonnet-4-6"
    end

    test "resolves claude haiku" do
      assert ModelProxy.resolve("claude", "haiku") == "claude-haiku-4-5-20251001"
    end

    test "resolves gemini opus to gemini-2.5-pro" do
      assert ModelProxy.resolve("gemini", "opus") == "gemini-2.5-pro"
    end

    test "resolves gemini haiku to gemini-2.0-flash" do
      assert ModelProxy.resolve("gemini", "haiku") == "gemini-2.0-flash"
    end

    test "resolves cursor opus to inherit" do
      assert ModelProxy.resolve("cursor", "opus") == "inherit"
    end

    test "resolves cursor haiku to fast" do
      assert ModelProxy.resolve("cursor", "haiku") == "fast"
    end

    test "resolves codex opus to o3" do
      assert ModelProxy.resolve("codex", "opus") == "o3"
    end

    test "resolves codex sonnet to o4-mini" do
      assert ModelProxy.resolve("codex", "sonnet") == "o4-mini"
    end

    test "passes through full model ID for known provider" do
      assert ModelProxy.resolve("claude", "gpt-4o") == "gpt-4o"
    end

    test "returns alias for unknown provider" do
      assert ModelProxy.resolve("unknown_provider", "opus") == "opus"
    end

    test "returns inherit for nil model alias" do
      assert ModelProxy.resolve("claude", nil) == "inherit"
    end
  end

  describe "providers/0" do
    test "returns all supported providers" do
      providers = ModelProxy.providers()
      assert "claude" in providers
      assert "gemini" in providers
      assert "cursor" in providers
      assert "codex" in providers
    end
  end

  describe "models_for/1" do
    test "returns model map for claude" do
      models = ModelProxy.models_for("claude")
      assert models["opus"] == "claude-opus-4-6"
      assert models["sonnet"] == "claude-sonnet-4-6"
      assert models["haiku"] == "claude-haiku-4-5-20251001"
    end

    test "returns empty map for unknown provider" do
      assert ModelProxy.models_for("unknown") == %{}
    end
  end
end
