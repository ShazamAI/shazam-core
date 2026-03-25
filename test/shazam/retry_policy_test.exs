defmodule Shazam.RetryPolicyTest do
  use ExUnit.Case, async: true

  alias Shazam.RetryPolicy

  @moduletag :retry_policy

  describe "should_retry?/1" do
    test "returns true when retry_count is below max_retries" do
      task = %{retry_count: 0, max_retries: 2}
      assert RetryPolicy.should_retry?(task)
    end

    test "returns true for retry_count 1 with max_retries 2" do
      task = %{retry_count: 1, max_retries: 2}
      assert RetryPolicy.should_retry?(task)
    end

    test "returns false when retry_count equals max_retries" do
      task = %{retry_count: 2, max_retries: 2}
      refute RetryPolicy.should_retry?(task)
    end

    test "returns false when retry_count exceeds max_retries" do
      task = %{retry_count: 5, max_retries: 2}
      refute RetryPolicy.should_retry?(task)
    end

    test "defaults retry_count to 0 when not set" do
      task = %{max_retries: 2}
      assert RetryPolicy.should_retry?(task)
    end

    test "defaults max_retries to 2 when not set" do
      task = %{retry_count: 1}
      assert RetryPolicy.should_retry?(task)
    end

    test "defaults both retry_count and max_retries when empty map" do
      assert RetryPolicy.should_retry?(%{})
    end

    test "returns false for cancelled task" do
      task = %{retry_count: 0, max_retries: 3, last_error: "Task cancelled by user"}
      refute RetryPolicy.should_retry?(task)
    end

    test "returns false for budget_exhausted error" do
      task = %{retry_count: 0, max_retries: 3, last_error: "budget exhausted for agent"}
      refute RetryPolicy.should_retry?(task)
    end

    test "returns false for rejected task" do
      task = %{retry_count: 0, max_retries: 3, last_error: "Task rejected by supervisor"}
      refute RetryPolicy.should_retry?(task)
    end

    test "non-retryable patterns are case-insensitive" do
      task = %{retry_count: 0, max_retries: 3, last_error: "BUDGET EXHAUSTED"}
      refute RetryPolicy.should_retry?(task)
    end

    test "returns true for retryable error with retries remaining" do
      task = %{retry_count: 0, max_retries: 2, last_error: "timeout connecting to API"}
      assert RetryPolicy.should_retry?(task)
    end

    test "handles nil last_error gracefully" do
      task = %{retry_count: 0, max_retries: 2, last_error: nil}
      assert RetryPolicy.should_retry?(task)
    end

    test "handles tuple error format" do
      task = %{retry_count: 0, max_retries: 2, last_error: {:error, :timeout}}
      assert RetryPolicy.should_retry?(task)
    end

    test "handles process_died error format" do
      task = %{retry_count: 0, max_retries: 2, last_error: {:process_died, :normal}}
      assert RetryPolicy.should_retry?(task)
    end
  end

  describe "next_delay/1" do
    test "first retry (count 0) returns 5000ms" do
      assert RetryPolicy.next_delay(0) == 5_000
    end

    test "second retry (count 1) returns 15000ms" do
      assert RetryPolicy.next_delay(1) == 15_000
    end

    test "third retry (count 2) returns 30000ms" do
      assert RetryPolicy.next_delay(2) == 30_000
    end

    test "higher retry counts are capped at 30000ms" do
      assert RetryPolicy.next_delay(3) == 30_000
      assert RetryPolicy.next_delay(10) == 30_000
      assert RetryPolicy.next_delay(100) == 30_000
    end
  end

  describe "build_retry_context/1" do
    test "returns empty string when no last_error" do
      task = %{retry_count: 1, max_retries: 2}
      assert RetryPolicy.build_retry_context(task) == ""
    end

    test "returns empty string when last_error is nil" do
      task = %{retry_count: 1, max_retries: 2, last_error: nil}
      assert RetryPolicy.build_retry_context(task) == ""
    end

    test "includes retry count and max retries in output" do
      task = %{retry_count: 1, max_retries: 3, last_error: "something broke"}
      result = RetryPolicy.build_retry_context(task)
      assert result =~ "[RETRY 1/3]"
    end

    test "includes the error message in output" do
      task = %{retry_count: 1, max_retries: 2, last_error: "connection timeout"}
      result = RetryPolicy.build_retry_context(task)
      assert result =~ "connection timeout"
    end

    test "includes instruction to try a different approach" do
      task = %{retry_count: 1, max_retries: 2, last_error: "failed"}
      result = RetryPolicy.build_retry_context(task)
      assert result =~ "try a different approach"
    end

    test "defaults retry_count to 0 when not set" do
      task = %{last_error: "oops"}
      result = RetryPolicy.build_retry_context(task)
      assert result =~ "[RETRY 0/2]"
    end

    test "defaults max_retries to 2 when not set" do
      task = %{retry_count: 1, last_error: "oops"}
      result = RetryPolicy.build_retry_context(task)
      assert result =~ "[RETRY 1/2]"
    end

    test "handles tuple error format" do
      task = %{retry_count: 0, max_retries: 2, last_error: {:error, :econnrefused}}
      result = RetryPolicy.build_retry_context(task)
      assert result =~ "econnrefused"
    end

    test "handles process_died error format" do
      task = %{retry_count: 0, max_retries: 2, last_error: {:process_died, :killed}}
      result = RetryPolicy.build_retry_context(task)
      assert result =~ "Process died"
      assert result =~ "killed"
    end
  end
end
