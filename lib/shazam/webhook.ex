defmodule Shazam.Webhook do
  @moduledoc "Sends HTTP webhooks for important events (task completion, failures, circuit breaker)."

  use GenServer
  require Logger

  @important_events ~w(task_completed task_failed circuit_breaker_tripped plan_approved)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Register a webhook URL for notifications."
  def register(url, opts \\ []) do
    GenServer.call(__MODULE__, {:register, url, opts})
  end

  @doc "Remove a webhook URL."
  def unregister(url) do
    GenServer.call(__MODULE__, {:unregister, url})
  end

  @doc "List registered webhooks."
  def list do
    GenServer.call(__MODULE__, :list)
  end

  @doc "Process an event and send to webhooks if relevant."
  def notify(event) do
    GenServer.cast(__MODULE__, {:notify, event})
  end

  @impl true
  def init(_opts) do
    webhooks = load_webhooks()
    {:ok, %{webhooks: webhooks}}
  end

  @impl true
  def handle_call({:register, url, opts}, _from, state) do
    webhook = %{
      url: url,
      events: Keyword.get(opts, :events, @important_events),
      secret: Keyword.get(opts, :secret),
      active: true,
      created_at: DateTime.utc_now()
    }

    webhooks = [webhook | state.webhooks] |> Enum.uniq_by(& &1.url)
    save_webhooks(webhooks)
    {:reply, :ok, %{state | webhooks: webhooks}}
  end

  def handle_call({:unregister, url}, _from, state) do
    webhooks = Enum.reject(state.webhooks, &(&1.url == url))
    save_webhooks(webhooks)
    {:reply, :ok, %{state | webhooks: webhooks}}
  end

  def handle_call(:list, _from, state) do
    {:reply, state.webhooks, state}
  end

  @impl true
  def handle_cast({:notify, event}, state) do
    event_type = event[:event] || event["event"]

    if event_type in @important_events do
      Enum.each(state.webhooks, fn webhook ->
        if webhook.active && event_type in webhook.events do
          send_webhook(webhook, event)
        end
      end)
    end

    {:noreply, state}
  end

  defp send_webhook(webhook, event) do
    Task.start(fn ->
      payload =
        Jason.encode!(%{
          event: event[:event] || event["event"],
          timestamp: DateTime.to_iso8601(DateTime.utc_now()),
          data: event
        })

      headers = [{~c"Content-Type", ~c"application/json"}]

      headers =
        if webhook.secret do
          signature =
            :crypto.mac(:hmac, :sha256, webhook.secret, payload)
            |> Base.encode16(case: :lower)

          [{~c"X-Shazam-Signature", String.to_charlist("sha256=#{signature}")} | headers]
        else
          headers
        end

      case :httpc.request(
             :post,
             {String.to_charlist(webhook.url), headers, ~c"application/json",
              String.to_charlist(payload)},
             [timeout: 5000],
             []
           ) do
        {:ok, {{_, status, _}, _, _}} when status in 200..299 ->
          Logger.debug("[Webhook] Sent to #{webhook.url}: #{status}")

        {:ok, {{_, status, _}, _, _}} ->
          Logger.warning("[Webhook] Failed #{webhook.url}: HTTP #{status}")

        {:error, reason} ->
          Logger.warning("[Webhook] Error #{webhook.url}: #{inspect(reason)}")
      end
    end)
  end

  defp load_webhooks do
    case Shazam.Store.load("webhooks") do
      {:ok, data} -> data
      _ -> []
    end
  end

  defp save_webhooks(webhooks) do
    Shazam.Store.save("webhooks", webhooks)
  end
end
