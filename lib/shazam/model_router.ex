defmodule Shazam.ModelRouter do
  @moduledoc "Auto-routes tasks to the optimal model based on complexity signals."

  require Logger

  @haiku "claude-haiku-4-5-20251001"
  @sonnet "claude-sonnet-4-6"
  @opus "claude-opus-4-6"

  @simple_keywords ~w(fix typo rename update bump delete remove css style format lint)
  @complex_keywords ~w(plan architect design refactor migrate restructure)
  @critical_keywords ~w(security audit review critical production deploy)

  @doc """
  Resolve the model for a task+agent combination.
  If agent.model is "auto" or nil, routes based on task signals.
  Otherwise returns the agent's fixed model.
  """
  def resolve(task, agent_profile) do
    agent_model = get_model(agent_profile)

    if agent_model == "auto" do
      resolved = route_by_signals(task)
      Logger.info("[ModelRouter] Task '#{task.title}' → #{resolved}")
      resolved
    else
      agent_model
    end
  end

  defp route_by_signals(task) do
    title = String.downcase(task.title || "")
    desc = task.description || ""
    retry = Map.get(task, :retry_count, 0) || 0

    cond do
      retry > 0 -> @sonnet
      has_keyword?(title, @critical_keywords) -> @opus
      has_keyword?(title, @complex_keywords) -> @sonnet
      String.length(desc) > 500 -> @sonnet
      has_keyword?(title, @simple_keywords) -> @haiku
      true -> @haiku
    end
  end

  defp has_keyword?(text, keywords) do
    Enum.any?(keywords, &String.contains?(text, &1))
  end

  defp get_model(%{model: m}), do: m || "auto"
  defp get_model(%{"model" => m}), do: m || "auto"
  defp get_model(_), do: "auto"

  @doc "Get cost estimate for a model per 1K tokens."
  def cost_per_1k(model) do
    cond do
      String.contains?(to_string(model), "haiku") -> 0.002
      String.contains?(to_string(model), "opus") -> 0.030
      true -> 0.0065
    end
  end
end
