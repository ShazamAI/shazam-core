defmodule Shazam.API.EventBusTest do
  use ExUnit.Case, async: false

  @moduletag :event_bus

  setup do
    # Ensure EventBus GenServer is running (may have been killed by other tests)
    unless GenServer.whereis(Shazam.API.EventBus), do: Shazam.API.EventBus.start_link([])
    :ok
  end

  describe "broadcast/1 and recent_events/0" do
    test "stores events in buffer" do
      Shazam.API.EventBus.broadcast(%{event: "test_event_1", data: "hello"})
      Shazam.API.EventBus.broadcast(%{event: "test_event_2", data: "world"})
      # Give GenServer time to process casts
      Process.sleep(50)

      events = Shazam.API.EventBus.recent_events()
      assert length(events) >= 2

      event_names = Enum.map(events, & &1[:event])
      assert "test_event_1" in event_names
      assert "test_event_2" in event_names
    end

    test "adds timestamp to events" do
      Shazam.API.EventBus.broadcast(%{event: "ts_test"})
      Process.sleep(50)

      events = Shazam.API.EventBus.recent_events()
      latest = Enum.find(events, & &1[:event] == "ts_test")
      assert latest != nil
      assert latest[:timestamp] != nil
    end

    test "limits buffer to 50 events" do
      for i <- 1..60 do
        Shazam.API.EventBus.broadcast(%{event: "overflow_#{i}"})
      end
      Process.sleep(100)

      events = Shazam.API.EventBus.recent_events()
      assert length(events) <= 50
    end
  end

  describe "subscribe/0 and broadcast delivery" do
    test "subscribers receive events" do
      Shazam.API.EventBus.subscribe()
      Shazam.API.EventBus.broadcast(%{event: "sub_test", value: 42})

      assert_receive {:event, %{event: "sub_test", value: 42}}, 1000
      Shazam.API.EventBus.unsubscribe()
    end
  end
end
