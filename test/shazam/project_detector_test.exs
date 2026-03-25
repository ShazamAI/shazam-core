defmodule Shazam.ProjectDetectorTest do
  use ExUnit.Case, async: true

  alias Shazam.ProjectDetector

  @moduletag :project_detector

  setup do
    tmp = Path.join(System.tmp_dir!(), "shazam_detector_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_cleanup(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp}
  end

  # ── detect/1 ────────────────────────────────────────────────

  describe "detect/1" do
    test "detects Node/JavaScript from package.json", %{tmp: tmp} do
      File.write!(Path.join(tmp, "package.json"), Jason.encode!(%{
        "dependencies" => %{"express" => "^4.0.0"}
      }))

      result = ProjectDetector.detect(tmp)

      assert result.language == "JavaScript"
      assert is_map(result.tech_stack)
      assert result.tech_stack.language == "JavaScript"
    end

    test "detects TypeScript when typescript dependency present", %{tmp: tmp} do
      File.write!(Path.join(tmp, "package.json"), Jason.encode!(%{
        "dependencies" => %{"typescript" => "^5.0.0"}
      }))

      result = ProjectDetector.detect(tmp)

      assert result.language == "TypeScript"
    end

    test "detects TypeScript from tsconfig.json", %{tmp: tmp} do
      File.write!(Path.join(tmp, "package.json"), Jason.encode!(%{
        "dependencies" => %{"express" => "^4.0.0"}
      }))
      File.write!(Path.join(tmp, "tsconfig.json"), "{}")

      result = ProjectDetector.detect(tmp)

      assert result.language == "TypeScript"
    end

    test "detects React framework", %{tmp: tmp} do
      File.write!(Path.join(tmp, "package.json"), Jason.encode!(%{
        "dependencies" => %{"react" => "^18.0.0"}
      }))

      result = ProjectDetector.detect(tmp)

      assert result.framework == "React"
    end

    test "detects Next.js framework", %{tmp: tmp} do
      File.write!(Path.join(tmp, "package.json"), Jason.encode!(%{
        "dependencies" => %{"next" => "^14.0.0", "react" => "^18.0.0"}
      }))

      result = ProjectDetector.detect(tmp)

      assert result.framework == "Next.js"
    end

    test "detects Nuxt framework", %{tmp: tmp} do
      File.write!(Path.join(tmp, "package.json"), Jason.encode!(%{
        "dependencies" => %{"nuxt" => "^3.0.0"}
      }))

      result = ProjectDetector.detect(tmp)

      assert result.framework == "Nuxt 3"
    end

    test "detects Tailwind CSS styling", %{tmp: tmp} do
      File.write!(Path.join(tmp, "package.json"), Jason.encode!(%{
        "devDependencies" => %{"tailwindcss" => "^3.0.0"}
      }))

      result = ProjectDetector.detect(tmp)

      assert result.styling == "Tailwind CSS"
    end

    test "detects Vitest testing framework", %{tmp: tmp} do
      File.write!(Path.join(tmp, "package.json"), Jason.encode!(%{
        "devDependencies" => %{"vitest" => "^1.0.0"}
      }))

      result = ProjectDetector.detect(tmp)

      assert result.testing == "Vitest"
    end

    test "detects Jest testing framework", %{tmp: tmp} do
      File.write!(Path.join(tmp, "package.json"), Jason.encode!(%{
        "devDependencies" => %{"jest" => "^29.0.0"}
      }))

      result = ProjectDetector.detect(tmp)

      assert result.testing == "Jest"
    end

    test "detects Prisma database", %{tmp: tmp} do
      File.write!(Path.join(tmp, "package.json"), Jason.encode!(%{
        "dependencies" => %{"@prisma/client" => "^5.0.0"}
      }))

      result = ProjectDetector.detect(tmp)

      assert result.database == "Prisma"
    end

    test "detects npm package manager from package-lock.json", %{tmp: tmp} do
      File.write!(Path.join(tmp, "package.json"), Jason.encode!(%{"dependencies" => %{}}))
      File.write!(Path.join(tmp, "package-lock.json"), "{}")

      result = ProjectDetector.detect(tmp)

      assert result.package_manager == "npm"
    end

    test "detects yarn package manager", %{tmp: tmp} do
      File.write!(Path.join(tmp, "package.json"), Jason.encode!(%{"dependencies" => %{}}))
      File.write!(Path.join(tmp, "yarn.lock"), "")

      result = ProjectDetector.detect(tmp)

      assert result.package_manager == "yarn"
    end

    test "detects pnpm package manager", %{tmp: tmp} do
      File.write!(Path.join(tmp, "package.json"), Jason.encode!(%{"dependencies" => %{}}))
      File.write!(Path.join(tmp, "pnpm-lock.yaml"), "")

      result = ProjectDetector.detect(tmp)

      assert result.package_manager == "pnpm"
    end

    test "detects bun package manager", %{tmp: tmp} do
      File.write!(Path.join(tmp, "package.json"), Jason.encode!(%{"dependencies" => %{}}))
      File.write!(Path.join(tmp, "bun.lockb"), "")

      result = ProjectDetector.detect(tmp)

      assert result.package_manager == "bun"
    end

    test "detects Elixir from mix.exs", %{tmp: tmp} do
      File.write!(Path.join(tmp, "mix.exs"), """
      defmodule MyApp.MixProject do
        use Mix.Project

        defp deps do
          []
        end
      end
      """)

      result = ProjectDetector.detect(tmp)

      assert result.language == "Elixir"
    end

    test "detects Phoenix framework from mix.exs", %{tmp: tmp} do
      File.write!(Path.join(tmp, "mix.exs"), """
      defmodule MyApp.MixProject do
        use Mix.Project

        defp deps do
          [{:phoenix, "~> 1.7"}]
        end
      end
      """)

      result = ProjectDetector.detect(tmp)

      assert result.language == "Elixir"
      assert result.framework == "Phoenix"
    end

    test "detects Phoenix LiveView from mix.exs", %{tmp: tmp} do
      File.write!(Path.join(tmp, "mix.exs"), """
      defmodule MyApp.MixProject do
        use Mix.Project

        defp deps do
          [{:phoenix, "~> 1.7"}, {:phoenix_live_view, "~> 0.20"}]
        end
      end
      """)

      result = ProjectDetector.detect(tmp)

      assert result.framework == "Phoenix LiveView"
    end

    test "detects ExUnit testing from mix.exs with test dir", %{tmp: tmp} do
      File.write!(Path.join(tmp, "mix.exs"), """
      defmodule MyApp.MixProject do
        use Mix.Project

        defp deps do
          [{:ex_unit, "~> 1.0"}]
        end
      end
      """)
      File.mkdir_p!(Path.join(tmp, "test"))

      result = ProjectDetector.detect(tmp)

      assert result.testing == "ExUnit"
    end

    test "detects PostgreSQL from mix.exs with ecto", %{tmp: tmp} do
      File.write!(Path.join(tmp, "mix.exs"), """
      defmodule MyApp.MixProject do
        defp deps do
          [{:ecto, "~> 3.0"}, {:postgrex, ">= 0.0.0"}]
        end
      end
      """)

      result = ProjectDetector.detect(tmp)

      assert result.database == "PostgreSQL"
    end

    test "detects Rust from Cargo.toml", %{tmp: tmp} do
      File.write!(Path.join(tmp, "Cargo.toml"), """
      [package]
      name = "my_app"
      version = "0.1.0"
      """)

      result = ProjectDetector.detect(tmp)

      assert result.language == "Rust"
    end

    test "detects Go from go.mod", %{tmp: tmp} do
      File.write!(Path.join(tmp, "go.mod"), """
      module example.com/myapp
      go 1.21
      """)

      result = ProjectDetector.detect(tmp)

      assert result.language == "Go"
    end

    test "detects Python from requirements.txt", %{tmp: tmp} do
      File.write!(Path.join(tmp, "requirements.txt"), "flask==2.0.0\n")

      result = ProjectDetector.detect(tmp)

      assert result.language == "Python"
      assert result.framework == "Flask"
    end

    test "detects Django framework from pyproject.toml", %{tmp: tmp} do
      File.write!(Path.join(tmp, "pyproject.toml"), """
      [project]
      dependencies = ["django>=4.0"]
      """)

      result = ProjectDetector.detect(tmp)

      assert result.language == "Python"
      assert result.framework == "Django"
    end

    test "detects Ruby from Gemfile", %{tmp: tmp} do
      File.write!(Path.join(tmp, "Gemfile"), """
      source "https://rubygems.org"
      gem "rails", "~> 7.0"
      """)

      result = ProjectDetector.detect(tmp)

      assert result.language == "Ruby"
      assert result.framework == "Ruby on Rails"
    end

    test "detects Dart/Flutter from pubspec.yaml", %{tmp: tmp} do
      File.write!(Path.join(tmp, "pubspec.yaml"), """
      name: my_app
      dependencies:
        flutter:
          sdk: flutter
      """)

      result = ProjectDetector.detect(tmp)

      assert result.language == "Dart"
      assert result.framework == "Flutter"
    end

    test "empty directory returns nil language and framework", %{tmp: tmp} do
      result = ProjectDetector.detect(tmp)

      assert result.language == nil
      assert result.framework == nil
      assert result.database == nil
      assert result.styling == nil
      assert result.testing == nil
      assert result.package_manager == nil
      assert result.monorepo == false
      assert result.ci_cd == false
    end

    test "detects monorepo from turbo.json", %{tmp: tmp} do
      File.write!(Path.join(tmp, "turbo.json"), "{}")

      result = ProjectDetector.detect(tmp)

      assert result.monorepo == true
    end

    test "detects monorepo from nx.json", %{tmp: tmp} do
      File.write!(Path.join(tmp, "nx.json"), "{}")

      result = ProjectDetector.detect(tmp)

      assert result.monorepo == true
    end

    test "detects monorepo from pnpm-workspace.yaml", %{tmp: tmp} do
      File.write!(Path.join(tmp, "pnpm-workspace.yaml"), "packages:\n  - packages/*")

      result = ProjectDetector.detect(tmp)

      assert result.monorepo == true
    end

    test "detects CI/CD from .github/workflows", %{tmp: tmp} do
      File.mkdir_p!(Path.join(tmp, ".github/workflows"))

      result = ProjectDetector.detect(tmp)

      assert result.ci_cd == true
    end

    test "detects CI/CD from .gitlab-ci.yml", %{tmp: tmp} do
      File.write!(Path.join(tmp, ".gitlab-ci.yml"), "stages: [build]")

      result = ProjectDetector.detect(tmp)

      assert result.ci_cd == true
    end

    test "detects Supabase from supabase directory", %{tmp: tmp} do
      File.mkdir_p!(Path.join(tmp, "supabase"))

      result = ProjectDetector.detect(tmp)

      assert result.database == "Supabase"
    end

    test "detects Prisma from prisma directory", %{tmp: tmp} do
      File.mkdir_p!(Path.join(tmp, "prisma"))

      result = ProjectDetector.detect(tmp)

      assert result.database == "Prisma"
    end

    test "detects PostgreSQL from docker-compose.yml", %{tmp: tmp} do
      File.write!(Path.join(tmp, "docker-compose.yml"), """
      services:
        db:
          image: postgres:15
      """)

      result = ProjectDetector.detect(tmp)

      assert result.database == "PostgreSQL"
    end

    test "result includes domains, suggested_agents, and tech_stack keys", %{tmp: tmp} do
      result = ProjectDetector.detect(tmp)

      assert Map.has_key?(result, :domains)
      assert Map.has_key?(result, :suggested_agents)
      assert Map.has_key?(result, :tech_stack)
      assert is_list(result.domains)
      assert is_list(result.suggested_agents)
      assert is_map(result.tech_stack)
    end
  end

  # ── detect_domains/1 ────────────────────────────────────────

  describe "detect_domains/1" do
    test "detects frontend domain from app/ and components/ dirs", %{tmp: tmp} do
      File.mkdir_p!(Path.join(tmp, "app"))
      File.mkdir_p!(Path.join(tmp, "components"))

      domains = ProjectDetector.detect_domains(tmp)
      domain_names = Enum.map(domains, & &1.name)

      assert "frontend" in domain_names

      frontend = Enum.find(domains, &(&1.name == "frontend"))
      assert "app/" in frontend.paths
      assert "components/" in frontend.paths
    end

    test "detects backend domain from lib/ and src/ dirs", %{tmp: tmp} do
      File.mkdir_p!(Path.join(tmp, "lib"))
      File.mkdir_p!(Path.join(tmp, "src"))

      domains = ProjectDetector.detect_domains(tmp)
      domain_names = Enum.map(domains, & &1.name)

      assert "backend" in domain_names

      backend = Enum.find(domains, &(&1.name == "backend"))
      assert "lib/" in backend.paths
      assert "src/" in backend.paths
    end

    test "detects backend domain from service dirs (supabase, server, api)", %{tmp: tmp} do
      File.mkdir_p!(Path.join(tmp, "server"))
      File.mkdir_p!(Path.join(tmp, "api"))

      domains = ProjectDetector.detect_domains(tmp)
      backend = Enum.find(domains, &(&1.name == "backend"))

      assert backend != nil
      assert "server/" in backend.paths
      assert "api/" in backend.paths
    end

    test "detects testing domain from test/ dir", %{tmp: tmp} do
      File.mkdir_p!(Path.join(tmp, "test"))

      domains = ProjectDetector.detect_domains(tmp)
      domain_names = Enum.map(domains, & &1.name)

      assert "testing" in domain_names
    end

    test "detects testing domain from tests/ and spec/ dirs", %{tmp: tmp} do
      File.mkdir_p!(Path.join(tmp, "tests"))
      File.mkdir_p!(Path.join(tmp, "spec"))

      domains = ProjectDetector.detect_domains(tmp)
      testing = Enum.find(domains, &(&1.name == "testing"))

      assert testing != nil
      assert "tests/" in testing.paths
      assert "spec/" in testing.paths
    end

    test "detects mobile domain", %{tmp: tmp} do
      File.mkdir_p!(Path.join(tmp, "ios"))
      File.mkdir_p!(Path.join(tmp, "android"))

      domains = ProjectDetector.detect_domains(tmp)
      mobile = Enum.find(domains, &(&1.name == "mobile"))

      assert mobile != nil
      assert "ios/" in mobile.paths
      assert "android/" in mobile.paths
    end

    test "returns empty list for empty directory", %{tmp: tmp} do
      assert ProjectDetector.detect_domains(tmp) == []
    end

    test "detects multiple domains simultaneously", %{tmp: tmp} do
      File.mkdir_p!(Path.join(tmp, "app"))
      File.mkdir_p!(Path.join(tmp, "lib"))
      File.mkdir_p!(Path.join(tmp, "test"))
      File.mkdir_p!(Path.join(tmp, "ios"))

      domains = ProjectDetector.detect_domains(tmp)
      domain_names = Enum.map(domains, & &1.name)

      assert "frontend" in domain_names
      assert "backend" in domain_names
      assert "testing" in domain_names
      assert "mobile" in domain_names
    end
  end

  # ── summary/1 ────────────────────────────────────────────────

  describe "summary/1" do
    test "returns formatted string with language and framework", %{tmp: tmp} do
      File.write!(Path.join(tmp, "package.json"), Jason.encode!(%{
        "dependencies" => %{"react" => "^18.0.0", "typescript" => "^5.0.0"},
        "devDependencies" => %{"tailwindcss" => "^3.0.0", "vitest" => "^1.0.0"}
      }))

      result = ProjectDetector.detect(tmp)
      text = ProjectDetector.summary(result)

      assert text =~ "Language:"
      assert text =~ "TypeScript"
      assert text =~ "Framework:"
      assert text =~ "React"
      assert text =~ "Styling:"
      assert text =~ "Tailwind CSS"
      assert text =~ "Testing:"
      assert text =~ "Vitest"
    end

    test "returns empty string for empty detection", %{tmp: tmp} do
      result = ProjectDetector.detect(tmp)
      text = ProjectDetector.summary(result)

      assert text == ""
    end

    test "includes domain names when domains detected", %{tmp: tmp} do
      File.mkdir_p!(Path.join(tmp, "lib"))
      File.mkdir_p!(Path.join(tmp, "test"))

      result = ProjectDetector.detect(tmp)
      text = ProjectDetector.summary(result)

      assert text =~ "Domains:"
      assert text =~ "backend"
      assert text =~ "testing"
    end

    test "includes monorepo indicator when detected", %{tmp: tmp} do
      File.write!(Path.join(tmp, "turbo.json"), "{}")

      result = ProjectDetector.detect(tmp)
      text = ProjectDetector.summary(result)

      assert text =~ "Monorepo:"
      assert text =~ "yes"
    end

    test "includes CI/CD indicator when detected", %{tmp: tmp} do
      File.mkdir_p!(Path.join(tmp, ".github/workflows"))

      result = ProjectDetector.detect(tmp)
      text = ProjectDetector.summary(result)

      assert text =~ "CI/CD:"
      assert text =~ "detected"
    end

    test "includes package manager when detected", %{tmp: tmp} do
      File.write!(Path.join(tmp, "package.json"), Jason.encode!(%{"dependencies" => %{}}))
      File.write!(Path.join(tmp, "yarn.lock"), "")

      result = ProjectDetector.detect(tmp)
      text = ProjectDetector.summary(result)

      assert text =~ "Package Manager:"
      assert text =~ "yarn"
    end
  end

  # ── suggest_agents/2 ─────────────────────────────────────────

  describe "suggest_agents/2" do
    test "always includes a PM agent" do
      agents = ProjectDetector.suggest_agents([], %{testing: nil})

      pm = Enum.find(agents, &(&1.name == "pm"))
      assert pm != nil
      assert pm.role == "Project Manager"
    end

    test "adds generic senior_dev when no specific domains", %{tmp: tmp} do
      result = ProjectDetector.detect(tmp)
      agents = result.suggested_agents

      assert Enum.any?(agents, &(&1.name == "senior_dev"))
    end

    test "adds frontend agent for frontend domain", %{tmp: tmp} do
      File.mkdir_p!(Path.join(tmp, "app"))

      result = ProjectDetector.detect(tmp)
      agents = result.suggested_agents

      assert Enum.any?(agents, &(&1.name == "senior_frontend"))
    end

    test "adds backend agent for backend domain", %{tmp: tmp} do
      File.mkdir_p!(Path.join(tmp, "lib"))

      result = ProjectDetector.detect(tmp)
      agents = result.suggested_agents

      assert Enum.any?(agents, &(&1.name == "senior_backend"))
    end

    test "adds mobile agent for mobile domain", %{tmp: tmp} do
      File.mkdir_p!(Path.join(tmp, "ios"))

      result = ProjectDetector.detect(tmp)
      agents = result.suggested_agents

      assert Enum.any?(agents, &(&1.name == "senior_mobile"))
    end

    test "adds QA agent when testing framework detected", %{tmp: tmp} do
      File.write!(Path.join(tmp, "package.json"), Jason.encode!(%{
        "devDependencies" => %{"vitest" => "^1.0.0"}
      }))

      result = ProjectDetector.detect(tmp)
      agents = result.suggested_agents

      assert Enum.any?(agents, &(&1.name == "qa"))
    end

    test "adds QA agent when testing domain exists", %{tmp: tmp} do
      File.mkdir_p!(Path.join(tmp, "test"))

      result = ProjectDetector.detect(tmp)
      agents = result.suggested_agents

      assert Enum.any?(agents, &(&1.name == "qa"))
    end
  end

  # ── Helper ──────────────────────────────────────────────────

  defp on_cleanup(fun) do
    ExUnit.Callbacks.on_exit(fun)
  end
end
