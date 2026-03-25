defmodule Shazam.API.WebSocket do
  @moduledoc """
  WebSocket handler for real-time communication with TUI, Dashboard, and Tray clients.
  Supports both the legacy API (get_tasks, get_statuses) and the full TUI protocol
  (commands, status, events, dashboard, task_list, agent_list, config).
  """

  @behaviour WebSock

  alias Shazam.API.WebSocketCommands

  @impl true
  def init(_opts) do
    Shazam.API.EventBus.subscribe()
    {:ok, %{company: nil, workspace: nil, agents: [], config: %{}}}
  end

  @impl true
  def handle_in({text, [opcode: :text]}, state) do
    case Jason.decode(text) do
      {:ok, msg} ->
        handle_message(msg, state)
      {:error, _} ->
        {:push, {:text, Jason.encode!(%{type: "event", event: "error", title: "Invalid JSON"})}, state}
    end
  end

  # ── Message Handlers ──────────────────────────────────

  # Subscribe to a project (TUI/Dashboard sends this on connect)
  defp handle_message(%{"action" => "subscribe", "company" => company} = msg, state) do
    workspace = msg["workspace"]
    agents = parse_agents(msg["agents"] || [])
    config = parse_config(msg["config"] || %{})

    if workspace do
      Application.put_env(:shazam, :workspace, workspace)
    end

    new_state = %{state |
      company: company,
      workspace: workspace,
      agents: agents,
      config: config
    }

    # Auto-register project in registry
    if company && workspace do
      agents = parse_agents(msg["agents"] || [])
      try do
        Shazam.ProjectRegistry.register(%{
          name: company,
          path: workspace,
          agents_count: length(agents)
        })
      catch
        _, _ -> :ok
      end
    end

    # Send initial status
    status = WebSocketCommands.build_status(new_state)
    {:push, {:text, Jason.encode!(status)}, new_state}
  end

  # TUI command (e.g., "/start", "/task Create login API", "/approve task_1")
  defp handle_message(%{"action" => "command", "raw" => raw}, state) do
    messages = WebSocketCommands.handle(raw, state)
    frames = Enum.map(messages, fn msg -> {:text, Jason.encode!(msg)} end)
    {:push, frames, state}
  end

  # Legacy: get tasks
  defp handle_message(%{"action" => "get_tasks"}, state) do
    tasks = Shazam.tasks() |> Enum.map(&serialize_task/1)
    {:push, {:text, Jason.encode!(%{event: "tasks", tasks: tasks})}, state}
  end

  # Legacy: get statuses
  defp handle_message(%{"action" => "get_statuses", "company" => name}, state) do
    statuses = Shazam.statuses(name)
    {:push, {:text, Jason.encode!(%{event: "statuses", agents: statuses})}, state}
  end

  # Request status update
  defp handle_message(%{"action" => "get_status"}, state) do
    status = WebSocketCommands.build_status(state)
    {:push, {:text, Jason.encode!(status)}, state}
  end

  # Paste data from TUI
  defp handle_message(%{"type" => "paste", "content" => content}, state) do
    # Store paste for expansion in commands
    paste_id = (state[:paste_count] || 0) + 1
    new_state = state
      |> Map.put(:paste_count, paste_id)
      |> Map.update(:paste_store, %{paste_id => content}, &Map.put(&1, paste_id, content))
    {:ok, new_state}
  end

  # Resize event (ignored server-side)
  defp handle_message(%{"type" => "resize"}, state) do
    {:ok, state}
  end

  # Unknown message
  defp handle_message(_msg, state) do
    {:ok, state}
  end

  # ── EventBus Events ──────────────────────────────────

  @impl true
  def handle_info({:event, event}, state) do
    # Filter events by subscribed company if set
    event_company = event[:company] || event["company"]

    should_forward = cond do
      state.company == nil -> true  # No filter, send all
      event_company == nil -> true  # Event has no company, send it
      event_company == state.company -> true
      true -> false
    end

    if should_forward do
      # Format and send events — may produce multiple messages (event + status update)
      messages = format_event_full(event, state)
      frames = Enum.map(messages, fn msg -> {:text, Jason.encode!(msg)} end)
      {:push, frames, state}
    else
      {:ok, state}
    end
  end

  def handle_info(_, state) do
    {:ok, state}
  end

  @impl true
  def terminate(_reason, _state) do
    Shazam.API.EventBus.unsubscribe()
    :ok
  end

  # ── Helpers ──────────────────────────────────────────

  @silent_events ~w(streaming chunk token delta heartbeat ping metrics_updated modules_claimed)

  defp format_event_full(event, state) do
    event_type = event[:event] || event["event"] || "unknown"
    ts = Calendar.strftime(DateTime.utc_now(), "%H:%M:%S")

    # Skip noisy events
    if event_type in @silent_events do
      []
    else
      main_msg = cond do
        # Agent output — show tool_use and text, skip text_delta
        event_type == "agent_output" ->
          agent = event[:agent] || event["agent"] || ""
          output_type = event[:type] || event["type"] || ""
          content = event[:content] || event["content"] || ""

          case output_type do
            "tool_use" ->
              %{type: "event", agent: agent, event: "tool_use",
                title: String.slice(to_string(content), 0..120), timestamp: ts}
            "text" ->
              first_line = content |> to_string() |> String.split("\n") |> List.first("")
              if String.length(first_line) > 5 do
                %{type: "event", agent: agent, event: "agent_output",
                  title: String.slice(first_line, 0..120), timestamp: ts}
              else
                nil
              end
            _ -> nil
          end

        # Task skipped — show reason
        event_type == "task_skipped" ->
          agent = event[:agent] || event["agent"] || ""
          reason = event[:reason] || event["reason"] || "unknown"
          task_id = event[:task_id] || event["task_id"] || ""
          %{type: "event", agent: agent, event: "task_skipped",
            title: "#{task_id}: #{reason}", timestamp: ts}

        # Approval request — send both event and approval message
        event_type == "task_awaiting_approval" ->
          agent = event[:agent] || event["agent"] || ""
          title = resolve_title(event)
          %{type: "event", agent: agent, event: event_type, title: title, timestamp: ts}

        # All other events
        true ->
          {agent, title} = resolve_event_details(event)
          if agent == "" and title == "" do
            nil
          else
            %{type: "event", agent: agent, event: event_type, title: title, timestamp: ts}
          end
      end

      messages = if main_msg, do: [main_msg], else: []

      # Send approval message for approval events
      messages = if event_type == "task_awaiting_approval" do
        task_id = event[:task_id] || event["task_id"]
        title = resolve_title(event)
        agent = event[:agent] || event["agent"] || ""
        messages ++ [%{
          type: "approval",
          task_id: task_id || "",
          title: to_string(title),
          agent: agent,
          description: event[:description] || event["description"]
        }]
      else
        messages
      end

      # Auto-send status update on relevant events
      status_events = ~w(task_created task_completed task_failed task_started task_approved task_rejected ralph_resumed ralph_paused task_killed task_paused task_resumed)
      if event_type in status_events do
        messages ++ [Shazam.API.WebSocketCommands.build_status(state)]
      else
        messages
      end
    end
  end

  defp resolve_title(event) do
    event[:title] || event["title"] || event[:text] || event["text"] || ""
  end

  defp resolve_event_details(event) do
    task_id = event[:task_id] || event["task_id"]
    raw_agent = event[:agent] || event["agent"] || event["assigned_to"] || ""
    raw_title = event[:title] || event["title"] || ""
    raw_text = event[:text] || event["text"] || ""

    if task_id && (raw_agent == "" or raw_title == "") do
      task_info = try do
        case Shazam.TaskBoard.get(task_id) do
          {:ok, t} -> t
          _ -> nil
        end
      catch
        _, _ -> nil
      end

      agent = if raw_agent == "" and task_info, do: task_info.assigned_to || "system", else: raw_agent
      title = cond do
        raw_title != "" -> raw_title
        raw_text != "" -> raw_text
        task_info -> "#{task_id}: #{task_info.title || ""}"
        true -> to_string(task_id)
      end

      {to_string(agent), title}
    else
      title = if raw_title != "", do: raw_title, else: raw_text
      {to_string(raw_agent), title}
    end
  end

  defp serialize_task(task) do
    %{
      id: task.id,
      title: task.title,
      status: to_string(task.status),
      assigned_to: task.assigned_to,
      result: if(is_binary(task.result), do: task.result, else: inspect(task.result))
    }
  end

  defp parse_agents(agents) when is_list(agents) do
    Enum.map(agents, fn a ->
      %{
        name: a["name"],
        role: a["role"],
        supervisor: a["supervisor"],
        workspace: a["workspace"],
        provider: a["provider"],
        budget: a["budget"],
        domain: a["domain"]
      }
    end)
  end
  defp parse_agents(_), do: []

  defp parse_config(config) when is_map(config) do
    %{
      provider: config["provider"],
      mission: config["mission"],
      ralph_config: atomize_keys(config["ralph_config"] || %{}),
      domain_config: config["domain_config"] || %{}
    }
  end
  defp parse_config(_), do: %{}

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      key = if is_binary(k), do: String.to_existing_atom(k), else: k
      {key, v}
    end)
  rescue
    _ -> map
  end
end
