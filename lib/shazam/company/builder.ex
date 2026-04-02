defmodule Shazam.Company.Builder do
  @moduledoc """
  Handles building AgentWorker structs from config and persisting company data to the Store.

  ## Merge semantics

  When partial agent data arrives (e.g. from the dashboard bulk PUT), we merge
  with the existing agent so that fields like `tools`, `model`, `system_prompt`
  are never silently dropped. See `merge_with_existing/2`.
  """

  alias Shazam.Store

  @doc """
  Transforms config agents into a list of `Shazam.AgentWorker` structs.

  Expects a config map with `:name` and `:agents` keys, where each agent
  is a map/struct with keys like `:name`, `:role`, `:supervisor`, etc.
  """
  def build_agent_configs(config) do
    build_agents_from_raw(config.agents, config.name)
  end

  @doc """
  Persists a company config (as received at startup) to the Store.
  """
  def save_company(config) do
    data = %{
      "name" => config.name,
      "mission" => config.mission,
      "agents" => Enum.map(config.agents, fn a ->
        %{
          "name" => a.name || a[:name],
          "role" => a.role || a[:role],
          "supervisor" => a[:supervisor],
          "domain" => a[:domain],
          "budget" => Shazam.Config.normalize_budget(a[:budget]),
          "heartbeat_interval" => a[:heartbeat_interval] || 60_000,
          "tools" => a[:tools] || [],
          "skills" => a[:skills] || [],
          "modules" => a[:modules] || [],
          "system_prompt" => a[:system_prompt],
          "model" => a[:model],
          "fallback_model" => a[:fallback_model],
          "provider" => a[:provider]
        }
      end)
    }

    Store.save("company:#{config.name}", data)
  end

  @doc """
  Persists the current company GenServer state to the Store.
  Used after in-flight mutations (e.g. update_agents, set_domain_paths).
  """
  def save_company_state(state) do
    data = %{
      "name" => state.name,
      "mission" => state.mission,
      "agents" => Enum.map(state.agents, fn a ->
        %{
          "name" => a.name,
          "role" => a.role,
          "supervisor" => a.supervisor,
          "domain" => a.domain,
          "budget" => a.budget,
          "heartbeat_interval" => a.heartbeat_interval,
          "tools" => a.tools,
          "skills" => a.skills,
          "modules" => a.modules,
          "system_prompt" => a.system_prompt,
          "model" => a.model,
          "fallback_model" => a.fallback_model,
          "provider" => a.provider
        }
      end),
      "domain_config" => state.domain_config
    }

    Store.save("company:#{state.name}", data)
  end

  @doc """
  Builds a list of `Shazam.AgentWorker` structs from raw string-keyed maps
  (e.g. from a web request or deserialized JSON).
  """
  def build_agents_from_raw(agents_raw, company_name) do
    Enum.map(agents_raw, fn a ->
      if is_struct(a, Shazam.AgentWorker) do
        %{a |
          company_ref: company_name,
          heartbeat_interval: a.heartbeat_interval || 60_000,
          tools: a.tools || [],
          skills: a.skills || [],
          modules: a.modules || []
        }
      else
        # Support both atom keys and string keys
        %Shazam.AgentWorker{
          name: g(a, :name),
          role: g(a, :role),
          supervisor: g(a, :supervisor),
          domain: g(a, :domain),
          budget: g(a, :budget),
          heartbeat_interval: g(a, :heartbeat_interval) || 60_000,
          tools: g(a, :tools) || [],
          skills: g(a, :skills) || [],
          modules: g(a, :modules) || [],
          system_prompt: g(a, :system_prompt),
          model: g(a, :model),
          fallback_model: g(a, :fallback_model),
          provider: g(a, :provider),
          company_ref: company_name
        }
      end
    end)
  end

  @doc """
  Merges a partial raw map (atom or string keys) with an existing AgentWorker.

  For each agent field, uses the incoming value if present; otherwise falls back
  to the existing struct value. This prevents field loss when the dashboard or
  API sends a partial update.
  """
  def merge_with_existing(raw, %Shazam.AgentWorker{} = existing) do
    %{
      "name" => existing.name,
      "role" => g(raw, :role) || existing.role,
      "supervisor" => pick(raw, :supervisor, existing.supervisor),
      "domain" => pick(raw, :domain, existing.domain),
      "budget" => pick(raw, :budget, existing.budget),
      "model" => pick(raw, :model, existing.model),
      "fallback_model" => pick(raw, :fallback_model, existing.fallback_model),
      "provider" => pick(raw, :provider, existing.provider),
      "tools" => g(raw, :tools) || existing.tools,
      "skills" => g(raw, :skills) || existing.skills,
      "modules" => g(raw, :modules) || existing.modules,
      "system_prompt" => pick(raw, :system_prompt, existing.system_prompt),
      "heartbeat_interval" => g(raw, :heartbeat_interval) || existing.heartbeat_interval
    }
  end

  # Pick a value from raw if the key is explicitly present (even if nil/false),
  # otherwise fall back to existing. This lets callers explicitly set a field to nil.
  defp pick(raw, key, existing) do
    str_key = Atom.to_string(key)

    cond do
      Map.has_key?(raw, key) -> Map.get(raw, key)
      Map.has_key?(raw, str_key) -> Map.get(raw, str_key)
      true -> existing
    end
  end

  # Get value from map with atom or string key
  defp g(map, key) when is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
