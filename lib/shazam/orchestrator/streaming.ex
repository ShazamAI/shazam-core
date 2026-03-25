defmodule Shazam.Orchestrator.Streaming do
  @moduledoc """
  Handles broadcasting agent events to the EventBus and batching text deltas.

  Text deltas are buffered and flushed every `@broadcast_batch_chars` characters
  to reduce broadcast volume (~400 broadcasts down to ~20 per task).
  """

  # Batch text deltas — send every N chars instead of per-chunk
  @broadcast_batch_chars 200

  @doc """
  Broadcasts an agent streaming event (text delta, tool use, or result) to the EventBus.

  Text deltas are buffered in the process dictionary and flushed when the buffer
  reaches `#{@broadcast_batch_chars}` characters, or when a non-delta event arrives.
  """
  def broadcast_agent_event(agent_name, message) do
    alias ClaudeCode.Message
    alias ClaudeCode.Message.PartialAssistantMessage
    alias ClaudeCode.Content

    cond do
      # Text delta — buffer and batch
      match?(%PartialAssistantMessage{}, message) and PartialAssistantMessage.text_delta?(message) ->
        text = case PartialAssistantMessage.extract_text(message) do
          {:ok, t} -> t
          _ -> ""
        end
        buffer = (Process.get(:text_delta_buffer) || "") <> (text || "")

        if String.length(buffer) >= @broadcast_batch_chars do
          Shazam.API.EventBus.broadcast(%{
            event: "agent_output",
            agent: agent_name,
            type: "text_delta",
            content: buffer
          })
          Process.put(:text_delta_buffer, "")
        else
          Process.put(:text_delta_buffer, buffer)
        end

      # Tool use — flush text buffer first, then broadcast tool
      match?(%Message.AssistantMessage{}, message) ->
        flush_text_buffer(agent_name)
        %Message.AssistantMessage{message: msg} = message
        Enum.each(msg.content, fn
          %Content.ToolUseBlock{name: tool_name, input: input} ->
            Shazam.API.EventBus.broadcast(%{
              event: "agent_output",
              agent: agent_name,
              type: "tool_use",
              content: "#{tool_name}: #{inspect(input, limit: 200)}"
            })

          %Content.TextBlock{text: text} ->
            Shazam.API.EventBus.broadcast(%{
              event: "agent_output",
              agent: agent_name,
              type: "text",
              content: text
            })

          _ ->
            :ok
        end)

      # Result — capture token usage and cost
      match?(%Message.ResultMessage{}, message) ->
        %Message.ResultMessage{} = result_msg = message

        # Extract token usage
        usage = result_msg.usage || %{}
        input_tokens = usage[:input_tokens] || 0
        output_tokens = usage[:output_tokens] || 0
        total_tokens = input_tokens + output_tokens
        cost_usd = result_msg.total_cost_usd || 0.0

        # Record token usage in metrics
        Shazam.Metrics.record_tokens(agent_name, total_tokens, cost_usd)

        # Broadcast usage event
        Shazam.API.EventBus.broadcast(%{
          event: "agent_output",
          agent: agent_name,
          type: "text",
          content: "Tokens: #{total_tokens} (in: #{input_tokens}, out: #{output_tokens}) | Cost: $#{Float.round(cost_usd, 4)}"
        })

        content =
          if result_msg.is_error do
            "Failed: #{format_result_error(result_msg.result)}"
          else
            "Completed"
          end

        notify_agent_result(agent_name, content)

      true ->
        :ok
    end
  rescue
    _ -> :ok
  end

  @doc """
  Flushes any remaining buffered text delta to the EventBus.
  Should be called after streaming completes to ensure no text is lost.
  """
  def flush_text_buffer(agent_name) do
    buffer = Process.get(:text_delta_buffer) || ""
    if buffer != "" do
      Shazam.API.EventBus.broadcast(%{
        event: "agent_output",
        agent: agent_name,
        type: "text_delta",
        content: buffer
      })
      Process.put(:text_delta_buffer, "")
    end
  end

  @doc """
  Broadcasts an agent result event to the EventBus.
  """
  def notify_agent_result(agent_name, content) do
    Shazam.API.EventBus.broadcast(%{
      event: "agent_output",
      agent: agent_name,
      type: "result",
      content: content
    })
  end

  @doc """
  Broadcasts an agent progress event to the EventBus.
  """
  def notify_agent_progress(agent_name, content) do
    Shazam.API.EventBus.broadcast(%{
      event: "agent_output",
      agent: agent_name,
      type: "text",
      content: content
    })
  end

  defp format_result_error(result) when is_binary(result), do: String.slice(result, 0, 300)
  defp format_result_error(result), do: inspect(result, limit: 200)
end
