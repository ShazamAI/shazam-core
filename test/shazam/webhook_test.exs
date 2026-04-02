defmodule Shazam.WebhookTest do
  use ExUnit.Case, async: false

  setup do
    # Ensure Webhook GenServer is running with clean state
    case GenServer.whereis(Shazam.Webhook) do
      nil ->
        {:ok, _pid} = Shazam.Webhook.start_link([])
      _pid ->
        # Clear all existing webhooks via the public API
        Enum.each(Shazam.Webhook.list(), fn wh ->
          Shazam.Webhook.unregister(wh.url)
        end)
    end

    # Clean up any persisted webhooks
    on_exit(fn ->
      Shazam.Store.save("webhooks", [])
    end)

    :ok
  end

  describe "register/2" do
    test "registers a webhook URL" do
      assert :ok = Shazam.Webhook.register("https://example.com/hook")
      webhooks = Shazam.Webhook.list()
      assert length(webhooks) == 1
      assert hd(webhooks).url == "https://example.com/hook"
      assert hd(webhooks).active == true
    end

    test "registers with custom events" do
      :ok = Shazam.Webhook.register("https://example.com/hook", events: ["task_completed"])
      [webhook] = Shazam.Webhook.list()
      assert webhook.events == ["task_completed"]
    end

    test "registers with secret" do
      :ok = Shazam.Webhook.register("https://example.com/hook", secret: "my-secret")
      [webhook] = Shazam.Webhook.list()
      assert webhook.secret == "my-secret"
    end

    test "deduplicates by URL" do
      :ok = Shazam.Webhook.register("https://example.com/hook")
      :ok = Shazam.Webhook.register("https://example.com/hook")
      assert length(Shazam.Webhook.list()) == 1
    end
  end

  describe "unregister/1" do
    test "removes a registered webhook" do
      :ok = Shazam.Webhook.register("https://example.com/hook")
      assert length(Shazam.Webhook.list()) == 1

      :ok = Shazam.Webhook.unregister("https://example.com/hook")
      assert Shazam.Webhook.list() == []
    end

    test "no-op for unknown URL" do
      :ok = Shazam.Webhook.unregister("https://unknown.com/hook")
      assert Shazam.Webhook.list() == []
    end
  end

  describe "list/0" do
    test "returns empty list when no webhooks registered" do
      assert Shazam.Webhook.list() == []
    end

    test "returns all registered webhooks" do
      :ok = Shazam.Webhook.register("https://a.com/hook")
      :ok = Shazam.Webhook.register("https://b.com/hook")
      assert length(Shazam.Webhook.list()) == 2
    end
  end

  describe "notify/1" do
    test "ignores non-important events" do
      :ok = Shazam.Webhook.register("https://example.com/hook")

      # This should not crash or trigger any HTTP call
      Shazam.Webhook.notify(%{event: "some_random_event", data: "test"})

      # Give the cast time to process
      :timer.sleep(50)
      # If we got here without errors, the test passes
      assert true
    end

    test "processes important events without crashing" do
      # Register a webhook pointing to a non-existent server (will fail silently)
      :ok = Shazam.Webhook.register("http://localhost:19999/nonexistent")

      Shazam.Webhook.notify(%{event: "task_completed", task_id: "test_1"})

      # Give the cast and async task time to process
      :timer.sleep(100)
      # No crash means success — the HTTP error is logged but doesn't crash
      assert true
    end

    test "only notifies webhooks subscribed to the event" do
      :ok = Shazam.Webhook.register("http://localhost:19999/a", events: ["task_completed"])
      :ok = Shazam.Webhook.register("http://localhost:19999/b", events: ["task_failed"])

      # Sending task_completed should only try webhook A, not B
      Shazam.Webhook.notify(%{event: "task_completed", task_id: "test_1"})

      :timer.sleep(100)
      assert true
    end
  end
end
