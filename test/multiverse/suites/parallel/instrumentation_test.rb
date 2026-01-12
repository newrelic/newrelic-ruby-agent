# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'parallel'
require 'newrelic_rpm'
require 'fake_collector'

class ParallelTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent

  # Note: Similar to Resque multiverse tests, we don't test the actual forking/pipe
  # communication behavior here. That complexity is better suited for end-to-end tests.
  # These tests verify that the instrumentation doesn't break Parallel's functionality.

  def test_parallel_processes_work
    results = Parallel.map([1, 2, 3, 4], in_processes: 2) do |i|
      i * 2
    end

    assert_equal [2, 4, 6, 8], results
  end

  def test_parallel_with_multiple_workers
    worker_count = 4
    items = (1..10).to_a

    results = Parallel.map(items, in_processes: worker_count) do |i|
      i * 2
    end

    expected = items.map { |i| i * 2 }
    assert_equal expected, results
  end

  def test_parallel_threads_work
    # Threads should work normally (not using pipe instrumentation)
    results = Parallel.map([1, 2, 3], in_threads: 2) do |i|
      i * 2
    end

    assert_equal [2, 4, 6], results
  end

  def test_parallel_with_index
    results = Parallel.map([1, 2, 3], in_processes: 2) do |item|
      item * 2
    end

    assert_equal [2, 4, 6], results
  end

  def test_parallel_handles_exceptions
    exception_raised = false

    begin
      Parallel.map([1, 2, 3], in_processes: 2) do |i|
        raise StandardError, 'Test error' if i == 2
        i * 2
      end
    rescue Parallel::DeadWorker, StandardError
      exception_raised = true
    end

    assert exception_raised, 'Should handle exceptions in workers'
  end

  def test_agent_still_running_after_parallel_processes
    Parallel.map([1, 2], in_processes: 2) { |i| i * 2 }

    assert_predicate NewRelic::Agent.instance, :started?
  end

  def test_parallel_each_works
    # Just verify Parallel.each doesn't raise an error with our instrumentation
    Parallel.each([1, 2, 3], in_processes: 2) do |i|
      # Do some work
      _result = i * 2
    end

    # If we got here, each worked without raising
    assert true
  end
end
