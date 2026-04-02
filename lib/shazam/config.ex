defmodule Shazam.Config do
  @moduledoc """
  Centralized configuration resolution for Shazam.
  Single source of truth for workspace, budget defaults, and runtime settings.
  """

  @doc """
  Resolve workspace path with consistent fallback chain:
  1. Agent-specific workspace (if configured)
  2. Global workspace from Application env
  3. Current working directory
  """
  def workspace(agent_profile \\ nil) do
    agent_ws = if agent_profile, do: Map.get(agent_profile, :workspace), else: nil

    if agent_ws do
      workspaces = Application.get_env(:shazam, :workspaces, %{})
      case Map.get(workspaces, agent_ws) do
        %{path: path} when is_binary(path) -> path
        _ -> global_workspace()
      end
    else
      global_workspace()
    end
  end

  @doc "Get the global workspace path."
  def global_workspace do
    Application.get_env(:shazam, :workspace) || File.cwd!()
  end

  @doc """
  Normalize budget value.
  - nil or 0 means unlimited
  - Positive integer means token limit
  """
  def normalize_budget(nil), do: nil
  def normalize_budget(0), do: nil
  def normalize_budget(budget) when is_integer(budget) and budget > 0, do: budget
  def normalize_budget(_), do: nil

  @doc "Check if budget is unlimited."
  def unlimited_budget?(nil), do: true
  def unlimited_budget?(0), do: true
  def unlimited_budget?(_), do: false

  @doc "Get the default poll interval in ms."
  def poll_interval do
    Application.get_env(:shazam, :poll_interval, 5_000)
  end

  @doc "Get max concurrent agents."
  def max_concurrent do
    Application.get_env(:shazam, :max_concurrent, 4)
  end
end
