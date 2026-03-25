defmodule Shazam.Orchestrator.Executor do
  @moduledoc """
  Handles query execution, touched-file collection, and text buffer flushing
  for the Orchestrator. Extracted to keep the main Orchestrator module thin.
  """

  require Logger

  alias Shazam.Orchestrator.Streaming

  @doc """
  Executes a prompt on a Claude session, collecting touched files and streaming events.

  Returns `{:ok, result_text, touched_files}` or `{:error, reason}`.
  """
  def execute_query(session, prompt, agent_name) do
    # Accumulate touched files (Edit, Write)
    touched_files = :ets.new(:touched_files, [:set, :private])

    # Text delta buffer — flush every N characters
    Process.put(:text_delta_buffer, "")

    stream = ClaudeCode.stream(session, prompt, include_partial_messages: true)

    stream =
      if agent_name do
        stream
        |> ClaudeCode.Stream.tap(fn message ->
          Streaming.broadcast_agent_event(agent_name, message)
          collect_touched_files(message, touched_files)
        end)
      else
        stream
      end

    # Collect full conversation summary (text + tool calls + result)
    summary = ClaudeCode.Stream.collect(stream)

    # Flush any remaining buffered text
    Streaming.flush_text_buffer(agent_name)

    files = :ets.tab2list(touched_files) |> Enum.map(fn {path} -> path end)
    :ets.delete(touched_files)

    # Extract text from summary (collect returns %{text: "...", result: %ResultMessage{}})
    text = summary.text || ""
    result_msg = summary.result

    case result_msg do
      %{is_error: true} = err -> {:error, err}
      %{result: r} when is_binary(r) and r != "" -> {:ok, r, files}
      _ ->
        # Fallback: use collected text if result field is empty
        if text != "" do
          {:ok, text, files}
        else
          {:error, :no_result}
        end
    end
  end

  @doc """
  Inspects a streaming message for Edit/Write tool uses and records
  the affected file paths in an ETS table.
  """
  def collect_touched_files(message, table) do
    alias ClaudeCode.Message
    alias ClaudeCode.Content

    if match?(%Message.AssistantMessage{}, message) do
      %Message.AssistantMessage{message: msg} = message
      Enum.each(msg.content, fn
        %Content.ToolUseBlock{name: tool_name, input: input}
            when tool_name in ["Edit", "Write"] ->
          path = input["file_path"] || input[:file_path]
          if path, do: :ets.insert(table, {path})

        _ ->
          :ok
      end)
    end
  rescue
    _ -> :ok
  end
end
