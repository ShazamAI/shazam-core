defmodule Shazam.ModelProxy do
  @moduledoc "Maps model aliases to provider-specific model IDs."

  @model_map %{
    "claude" => %{
      "opus" => "claude-opus-4-6",
      "sonnet" => "claude-sonnet-4-6",
      "haiku" => "claude-haiku-4-5-20251001"
    },
    "gemini" => %{
      "opus" => "gemini-2.5-pro",
      "sonnet" => "gemini-2.5-pro",
      "haiku" => "gemini-2.0-flash"
    },
    "cursor" => %{
      "opus" => "inherit",
      "sonnet" => "inherit",
      "haiku" => "fast"
    },
    "codex" => %{
      "opus" => "o3",
      "sonnet" => "o4-mini",
      "haiku" => "o4-mini"
    }
  }

  @doc "Resolve a model alias (opus/sonnet/haiku) to a provider-specific ID."
  def resolve(provider, model_alias) do
    provider_map = @model_map[provider] || %{}
    # Check if it's an alias or already a full model ID
    provider_map[model_alias] || model_alias || "inherit"
  end

  @doc "Get all supported providers."
  def providers, do: Map.keys(@model_map)

  @doc "Get model map for a provider."
  def models_for(provider), do: @model_map[provider] || %{}
end
