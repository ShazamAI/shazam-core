defmodule Shazam.TaskComplexity do
  @moduledoc "Analyzes task complexity and suggests decomposition."

  @doc """
  Analyze a task and return complexity assessment.
  Returns :simple, {:complex, reasons}, or {:suggest_decomposition, reasons, estimated_subtasks}
  """
  def analyze(attrs) do
    title = to_string(attrs[:title] || attrs["title"] || "")
    description = to_string(attrs[:description] || attrs["description"] || "")
    full_text = title <> " " <> description

    reasons = []

    # Check signals
    reasons = if String.length(description) > 500, do: ["Long description (#{String.length(description)} chars)" | reasons], else: reasons
    reasons = if count_keywords(full_text, ~w(and also plus additionally furthermore moreover)) > 2, do: ["Multiple requirements detected" | reasons], else: reasons
    reasons = if count_keywords(full_text, ~w(step steps phase phases first then after finally)) > 2, do: ["Multi-step workflow" | reasons], else: reasons
    reasons = if count_keywords(full_text, ~w(create build implement add)) > 3, do: ["Multiple creation tasks" | reasons], else: reasons
    reasons = if count_files_mentioned(full_text) > 5, do: ["#{count_files_mentioned(full_text)} files mentioned" | reasons], else: reasons
    reasons = if count_bullet_points(description) > 4, do: ["#{count_bullet_points(description)} bullet points" | reasons], else: reasons

    estimated = estimate_subtask_count(reasons, full_text)

    cond do
      length(reasons) >= 3 -> {:suggest_decomposition, Enum.reverse(reasons), estimated}
      length(reasons) >= 1 -> {:complex, Enum.reverse(reasons)}
      true -> :simple
    end
  end

  @doc "Quick check if task should suggest decomposition."
  def should_decompose?(attrs) do
    case analyze(attrs) do
      {:suggest_decomposition, _, _} -> true
      _ -> false
    end
  end

  defp count_keywords(text, keywords) do
    lower = String.downcase(text)
    Enum.count(keywords, &String.contains?(lower, &1))
  end

  defp count_files_mentioned(text) do
    Regex.scan(~r/\b[\w\/]+\.\w{1,5}\b/, text) |> length()
  end

  defp count_bullet_points(text) do
    text |> String.split("\n") |> Enum.count(fn line ->
      trimmed = String.trim(line)
      String.starts_with?(trimmed, "- ") || String.starts_with?(trimmed, "* ") || Regex.match?(~r/^\d+[\.\)]\s/, trimmed)
    end)
  end

  defp estimate_subtask_count(reasons, text) do
    base = length(reasons)
    bullets = count_bullet_points(text)
    max(base, min(bullets, 8))
  end
end
