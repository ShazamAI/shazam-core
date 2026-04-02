defmodule Shazam.AuditLog do
  @moduledoc "Records audit trail of important actions for compliance and debugging."

  use GenServer
  require Logger

  @max_entries 1000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Record an audit event."
  def record(action, details \\ %{}) do
    GenServer.cast(__MODULE__, {:record, action, details})
  end

  @doc "Get recent audit entries."
  def recent(limit \\ 50) do
    GenServer.call(__MODULE__, {:recent, limit})
  end

  @doc "Get entries filtered by action type."
  def filter(action_type, limit \\ 50) do
    GenServer.call(__MODULE__, {:filter, action_type, limit})
  end

  @impl true
  def init(_opts) do
    entries = load_entries()
    {:ok, %{entries: entries}}
  end

  @impl true
  def handle_cast({:record, action, details}, state) do
    entry = %{
      id: System.unique_integer([:positive]),
      action: action,
      details: details,
      timestamp: DateTime.to_iso8601(DateTime.utc_now())
    }

    entries = [entry | state.entries] |> Enum.take(@max_entries)
    save_entries(entries)

    {:noreply, %{state | entries: entries}}
  end

  @impl true
  def handle_call({:recent, limit}, _from, state) do
    {:reply, Enum.take(state.entries, limit), state}
  end

  def handle_call({:filter, action_type, limit}, _from, state) do
    filtered =
      state.entries
      |> Enum.filter(fn e -> e.action == action_type end)
      |> Enum.take(limit)

    {:reply, filtered, state}
  end

  defp load_entries do
    case Shazam.Store.load("audit_log") do
      {:ok, entries} when is_list(entries) ->
        Enum.map(entries, fn e ->
          %{
            id: e["id"] || System.unique_integer([:positive]),
            action: e["action"],
            details: e["details"] || %{},
            timestamp: e["timestamp"]
          }
        end)

      _ ->
        []
    end
  end

  defp save_entries(entries) do
    Shazam.Store.save("audit_log", entries)
  end
end
