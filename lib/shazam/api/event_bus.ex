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

  @impl true
  def init(_) do
    {:ok, %{subscribers: MapSet.new()}}
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

  def handle_cast({:broadcast, event}, state) do
    Enum.each(state.subscribers, fn pid ->
      send(pid, {:event, event})
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end
end
