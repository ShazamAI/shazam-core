defmodule Shazam.CircuitBreakerTest do
  use ExUnit.Case, async: false

  @moduletag :circuit_breaker

  setup do
    # Reset circuit breaker before each test
    Shazam.CircuitBreaker.reset()
    :ok
  end

  describe "tripped?/0" do
    test "starts not tripped" do
      refute Shazam.CircuitBreaker.tripped?()
    end

    test "trips after 3 consecutive failures" do
      Shazam.CircuitBreaker.record_failure("error 1")
      Shazam.CircuitBreaker.record_failure("error 2")
      Shazam.CircuitBreaker.record_failure("error 3")
      # Give GenServer time to process
      Process.sleep(50)

      assert Shazam.CircuitBreaker.tripped?()
    end

    test "does not trip after 2 failures" do
      Shazam.CircuitBreaker.record_failure("error 1")
      Shazam.CircuitBreaker.record_failure("error 2")
      Process.sleep(50)

      refute Shazam.CircuitBreaker.tripped?()
    end
  end

  describe "record_success/0" do
    test "resets failure count" do
      Shazam.CircuitBreaker.record_failure("error 1")
      Shazam.CircuitBreaker.record_failure("error 2")
      Shazam.CircuitBreaker.record_success()
      Shazam.CircuitBreaker.record_failure("error 3")
      Process.sleep(50)

      refute Shazam.CircuitBreaker.tripped?()
    end
  end

  describe "reset/0" do
    test "clears tripped state" do
      Shazam.CircuitBreaker.record_failure("e1")
      Shazam.CircuitBreaker.record_failure("e2")
      Shazam.CircuitBreaker.record_failure("e3")
      Process.sleep(50)
      assert Shazam.CircuitBreaker.tripped?()

      Shazam.CircuitBreaker.reset()
      Process.sleep(50)
      refute Shazam.CircuitBreaker.tripped?()
    end
  end
end
