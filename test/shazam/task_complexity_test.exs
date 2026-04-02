defmodule Shazam.TaskComplexityTest do
  use ExUnit.Case, async: true

  alias Shazam.TaskComplexity

  describe "analyze/1" do
    test "simple task returns :simple" do
      assert :simple == TaskComplexity.analyze(%{title: "Fix button color", description: "Change from red to blue"})
    end

    test "long description returns complex" do
      long_desc = String.duplicate("This is a detailed requirement. ", 20)
      result = TaskComplexity.analyze(%{title: "Task", description: long_desc})
      assert {:complex, reasons} = result
      assert Enum.any?(reasons, &String.contains?(&1, "Long description"))
    end

    test "multiple conjunction keywords returns complex or suggest_decomposition" do
      attrs = %{
        title: "Build auth and also add dashboard plus setup CI",
        description: "Additionally configure monitoring and furthermore add logging"
      }
      result = TaskComplexity.analyze(attrs)
      assert result != :simple
    end

    test "multi-step workflow keywords trigger complexity" do
      attrs = %{
        title: "Migration steps",
        description: "First create the schema, then migrate data, after that validate, finally deploy the changes in phases"
      }
      result = TaskComplexity.analyze(attrs)
      assert result != :simple
    end

    test "multiple creation keywords trigger complexity" do
      attrs = %{
        title: "Build and create the full stack",
        description: "Implement the backend API, add the frontend, create database models, build the deployment pipeline"
      }
      result = TaskComplexity.analyze(attrs)
      assert result != :simple
    end

    test "many files mentioned triggers complexity" do
      attrs = %{
        title: "Update config files",
        description: """
        Update src/main.ts, src/app.vue, src/router.ts,
        lib/server.ex, lib/config.ex, config/runtime.exs,
        package.json and mix.exs
        """
      }
      result = TaskComplexity.analyze(attrs)
      assert result != :simple
    end

    test "many bullet points triggers complexity" do
      attrs = %{
        title: "Feature list",
        description: """
        - Add user auth
        - Create profile page
        - Build settings panel
        - Implement notifications
        - Add email integration
        - Setup CI/CD pipeline
        """
      }
      result = TaskComplexity.analyze(attrs)
      assert result != :simple
    end

    test "suggest_decomposition when multiple signals combine" do
      attrs = %{
        title: "Build complete auth system and also add OAuth plus create admin panel",
        description: """
        First set up the database schema for users and permissions.
        Then implement the registration and login flows step by step.
        After that, build the OAuth integration.
        Finally, create the admin dashboard.

        Files to modify:
        - lib/auth.ex
        - lib/oauth.ex
        - lib/admin.ex
        - lib/schema/user.ex
        - lib/schema/permission.ex
        - config/auth.exs

        Requirements:
        - Add JWT token handling
        - Create session management
        - Build password reset flow
        - Implement role-based access
        - Add audit logging
        """
      }
      result = TaskComplexity.analyze(attrs)
      assert {:suggest_decomposition, reasons, estimated} = result
      assert length(reasons) >= 3
      assert estimated >= 3
    end
  end

  describe "should_decompose?/1" do
    test "returns false for simple tasks" do
      refute TaskComplexity.should_decompose?(%{title: "Fix typo", description: ""})
    end

    test "returns false for complex but not decomposition-worthy tasks" do
      refute TaskComplexity.should_decompose?(%{
        title: "Fix bug",
        description: String.duplicate("Detail about the bug. ", 20)
      })
    end

    test "returns true for highly complex tasks" do
      attrs = %{
        title: "Build and create the full system also add tests plus deploy",
        description: """
        First implement the backend step by step.
        Then create the frontend after the API is done.
        Finally deploy everything in phases.

        - Add models
        - Build API
        - Create UI
        - Write tests
        - Deploy
        """
      }
      assert TaskComplexity.should_decompose?(attrs)
    end
  end

  describe "edge cases" do
    test "handles nil attrs gracefully" do
      assert :simple == TaskComplexity.analyze(%{})
    end

    test "handles string keys" do
      assert :simple == TaskComplexity.analyze(%{"title" => "Simple task", "description" => "Do it"})
    end

    test "handles atom keys" do
      assert :simple == TaskComplexity.analyze(%{title: "Simple task", description: "Do it"})
    end
  end
end
