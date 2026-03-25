defmodule ShazamCore.MixProject do
  use Mix.Project

  @version "0.5.3"

  def project do
    [
      app: :shazam,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Shazam Core",
      description: "AI Agent Orchestration engine — the backend of Shazam"
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Shazam.Application, []}
    ]
  end

  defp deps do
    [
      {:claude_code, "~> 0.33"},
      {:bandit, "~> 1.0"},
      {:plug, "~> 1.16"},
      {:jason, "~> 1.4"},
      {:cors_plug, "~> 3.0"},
      {:websock_adapter, "~> 0.5"},
      {:yaml_elixir, "~> 2.9"},
      {:sentry, "~> 10.0"},
      {:hackney, "~> 1.8"}
    ]
  end
end
