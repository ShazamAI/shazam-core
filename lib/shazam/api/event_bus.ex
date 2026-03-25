defmodule Shazam.API.EventBus do
  @moduledoc """
  PubSub simples para broadcast de eventos para WebSocket clients.
  """

  use GenServer

  @doc false
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc "Subscribes the calling process to receive `{:event, event}` messages."
  def subscribe do
    GenServer.call(__MODULE__, {:subscribe, self()})
  end

  @doc "Unsubscribes the calling process from event broadcasts."
  def unsubscribe do
    GenServer.cast(__MODULE__, {:unsubscribe, self()})
  end

  @doc "Broadcasts an event to all subscribed processes."
  def broadcast(event) do
    GenServer.cast(__MODULE__, {:broadcast, event})
  end

  @doc "Returns the last 50 events."
  def recent_events do
    GenServer.call(__MODULE__, :recent_events)
  catch
    _, _ -> []
  end

  @impl true
  def init(_) do
    {:ok, %{subscribers: MapSet.new(), buffer: :queue.new(), buffer_size: 0}}
  end

  @impl true
  def handle_call({:subscribe, pid}, _from, state) do
    Process.monitor(pid)
    {:reply, :ok, %{state | subscribers: MapSet.put(state.subscribers, pid)}}
  end

  @impl true
  def handle_cast({:unsubscribe, pid}, state) do
    {:noreply, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end

  @impl true
  def handle_call(:recent_events, _from, state) do
    events = :queue.to_list(state.buffer)
    {:reply, Enum.reverse(events), state}
  end

  def handle_cast({:broadcast, event}, state) do
    Enum.each(state.subscribers, fn pid ->
      send(pid, {:event, event})
    end)

    # Add timestamp if missing
    event = Map.put_new(event, :timestamp, DateTime.to_iso8601(DateTime.utc_now()))

    # Buffer last 50 events
    {buffer, size} = if state.buffer_size >= 50 do
      {_, q} = :queue.out(state.buffer)
      {:queue.in(event, q), 50}
    else
      {:queue.in(event, state.buffer), state.buffer_size + 1}
    end

    {:noreply, %{state | buffer: buffer, buffer_size: size}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end
end
