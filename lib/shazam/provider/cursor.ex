defmodule Shazam.Provider.Cursor do
  @moduledoc """
  Provider implementation for Cursor Agent CLI.
  Uses `cursor-agent` binary with prompt as positional argument.
  Stateless — each execution spawns a new CLI process.
  """

  @behaviour Shazam.Provider

  require Logger

  @default_timeout 600_000

  @impl true
  def name, do: "cursor"

  @impl true
  def supports_sessions?, do: false

  @impl true
  def available? do
    System.find_executable("cursor-agent") != nil or
      System.find_executable("cursor") != nil
  end

  @impl true
  def start_session(_opts), do: {:ok, :stateless}

  @impl true
  def stop_session(_session), do: :ok

  @impl true
  def execute(_session, prompt, opts \\ []) do
    agent_name = Keyword.get(opts, :agent_name, "cursor")
    system_prompt = Keyword.get(opts, :system_prompt, "")
    model = Keyword.get(opts, :model)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    workspace = Keyword.get(opts, :cwd, File.cwd!())

    cli_bin = System.find_executable("cursor-agent") || System.find_executable("cursor")

    case cli_bin do
      nil ->
        {:error, {:cursor_cli_not_found, "cursor-agent"}}

      bin ->
        combined_prompt = if system_prompt != "" do
          "#{system_prompt}\n\n#{prompt}"
        else
          prompt
        end

        args = [combined_prompt, "--print", "--workspace", workspace, "--force"]
        args = if model, do: args ++ ["--model", model], else: args

        notify(agent_name, "Starting Cursor Agent execution...")

        task = Task.async(fn ->
          System.cmd(bin, args, stderr_to_stdout: true, cd: workspace)
        end)

        case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
          {:ok, {output, 0}} ->
            notify(agent_name, "Completed via Cursor Agent")
            {:ok, String.trim(output), []}

          {:ok, {output, status}} ->
            {:error, {:cursor_exit_status, status, String.slice(output, 0, 2000)}}

          nil ->
            {:error, {:cursor_timeout, timeout}}
        end
    end
  end

  defp notify(agent_name, content) do
    Shazam.API.EventBus.broadcast(%{
      event: "agent_output", agent: agent_name, type: "text", content: content
    })
  rescue
    _ -> :ok
  end
end
