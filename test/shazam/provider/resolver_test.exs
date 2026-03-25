defmodule Shazam.Provider.ResolverTest do
  use ExUnit.Case, async: true

  alias Shazam.Provider.Resolver

  @moduletag :provider_resolver

  describe "resolve/1" do
    test "nil returns default provider (ClaudeCode)" do
      assert Resolver.resolve(nil) == Shazam.Provider.ClaudeCode
    end

    test "empty string returns default provider (ClaudeCode)" do
      assert Resolver.resolve("") == Shazam.Provider.ClaudeCode
    end

    test "resolves 'claude_code' to ClaudeCode" do
      assert Resolver.resolve("claude_code") == Shazam.Provider.ClaudeCode
    end

    test "resolves 'claude' to ClaudeCode" do
      assert Resolver.resolve("claude") == Shazam.Provider.ClaudeCode
    end

    test "resolves 'codex' to Codex" do
      assert Resolver.resolve("codex") == Shazam.Provider.Codex
    end

    test "resolves 'cursor' to Cursor" do
      assert Resolver.resolve("cursor") == Shazam.Provider.Cursor
    end

    test "resolves 'gemini' to Gemini" do
      assert Resolver.resolve("gemini") == Shazam.Provider.Gemini
    end

    test "resolves case-insensitively" do
      assert Resolver.resolve("CLAUDE_CODE") == Shazam.Provider.ClaudeCode
      assert Resolver.resolve("Codex") == Shazam.Provider.Codex
      assert Resolver.resolve("CURSOR") == Shazam.Provider.Cursor
      assert Resolver.resolve("Gemini") == Shazam.Provider.Gemini
    end

    test "unknown provider string returns default (ClaudeCode)" do
      assert Resolver.resolve("unknown_provider") == Shazam.Provider.ClaudeCode
    end

    test "resolves atom :codex to Codex" do
      assert Resolver.resolve(:codex) == Shazam.Provider.Codex
    end

    test "resolves atom :cursor to Cursor" do
      assert Resolver.resolve(:cursor) == Shazam.Provider.Cursor
    end

    test "resolves atom :gemini to Gemini" do
      assert Resolver.resolve(:gemini) == Shazam.Provider.Gemini
    end

    test "resolves atom :claude_code to ClaudeCode" do
      assert Resolver.resolve(:claude_code) == Shazam.Provider.ClaudeCode
    end

    test "unknown atom returns default (ClaudeCode)" do
      assert Resolver.resolve(:nonexistent_provider) == Shazam.Provider.ClaudeCode
    end
  end

  describe "available_providers/0" do
    test "returns a list" do
      result = Resolver.available_providers()
      assert is_list(result)
    end
  end
end
