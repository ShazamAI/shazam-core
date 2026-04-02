defmodule Shazam.ModelRouterTest do
  use ExUnit.Case, async: true

  alias Shazam.ModelRouter

  @haiku "claude-haiku-4-5-20251001"
  @sonnet "claude-sonnet-4-6"
  @opus "claude-opus-4-6"

  defp task(attrs \\ %{}) do
    Map.merge(%{title: "do something", description: "", retry_count: 0}, attrs)
  end

  defp agent(model \\ nil), do: %{model: model}

  describe "resolve/2 with auto routing" do
    test "simple task keywords route to haiku" do
      for kw <- ~w(fix typo rename update bump delete remove css style format lint) do
        t = task(%{title: "#{kw} the button color"})
        assert ModelRouter.resolve(t, agent()) == @haiku
      end
    end

    test "complex task keywords route to sonnet" do
      for kw <- ~w(plan architect design refactor migrate restructure) do
        t = task(%{title: "#{kw} the auth system"})
        assert ModelRouter.resolve(t, agent()) == @sonnet
      end
    end

    test "critical task keywords route to opus" do
      for kw <- ~w(security audit review critical production deploy) do
        t = task(%{title: "#{kw} the payment flow"})
        assert ModelRouter.resolve(t, agent()) == @opus
      end
    end

    test "retry > 0 routes to sonnet" do
      t = task(%{title: "fix button", retry_count: 1})
      assert ModelRouter.resolve(t, agent()) == @sonnet
    end

    test "long description routes to sonnet" do
      long_desc = String.duplicate("a", 501)
      t = task(%{title: "do something", description: long_desc})
      assert ModelRouter.resolve(t, agent()) == @sonnet
    end

    test "default routes to haiku" do
      t = task(%{title: "something unknown"})
      assert ModelRouter.resolve(t, agent()) == @haiku
    end

    test "nil model triggers auto routing" do
      t = task(%{title: "security check"})
      assert ModelRouter.resolve(t, %{model: nil}) == @opus
    end
  end

  describe "resolve/2 with fixed model" do
    test "returns fixed model when not auto" do
      t = task(%{title: "security check"})
      assert ModelRouter.resolve(t, %{model: "claude-sonnet-4-6"}) == "claude-sonnet-4-6"
    end

    test "string-keyed map works" do
      t = task(%{title: "security check"})
      assert ModelRouter.resolve(t, %{"model" => "my-model"}) == "my-model"
    end
  end

  describe "cost_per_1k/1" do
    test "haiku cost" do
      assert ModelRouter.cost_per_1k(@haiku) == 0.002
    end

    test "sonnet cost" do
      assert ModelRouter.cost_per_1k(@sonnet) == 0.0065
    end

    test "opus cost" do
      assert ModelRouter.cost_per_1k(@opus) == 0.030
    end
  end
end
