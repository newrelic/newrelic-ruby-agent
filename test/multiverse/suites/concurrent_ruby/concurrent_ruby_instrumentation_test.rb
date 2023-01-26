# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class ConcurrentRubyInstrumentationTest < Minitest::Test
  EXPECTED_SEGMENTS_FOR_NESTED_CALLS = [
    'Concurrent/Task',
    'External/www.example.com/Net::HTTP/GET'
  ]

  # Helper methods
  def future_in_transaction(&block)
    in_transaction do
      future = Concurrent::Promises.future { yield }
      future.wait!
    end
  end

  def concurrent_promises_calls_net_http_in_block
    future_in_transaction { Net::HTTP.get(URI('http://www.example.com')) }
  end

  def simulate_error
    future = Concurrent::Promises.future { raise 'hi' }
    future.wait!
  end

  def assert_segment_noticed_simulated_error(txn)
    assert_segment_noticed_error txn, /Concurrent\/Task$/, /RuntimeError/, /hi/i
  end

  def assert_expected_segments_in_transaction(txn)
    assert_predicate (txn.segments.map(&:name) & EXPECTED_SEGMENTS_FOR_NESTED_CALLS), :any?
  end

  # Tests
  def test_promises_future_creates_segment_with_default_name
    txn = future_in_transaction { 'time keeps on slipping' }
    expected_segment = 'Concurrent/Task'

    # concurrent ruby sometimes reuses threads, so in that case there would be no segment for the thread being created.
    # this removes any thread segment since it may or may not exist, depending on what concurrent ruby decided to do
    non_thread_segments = txn.segments.select { |seg| seg.name != 'Ruby/Thread' }

    assert_equal(2, non_thread_segments.length)
    assert_includes txn.segments.map(&:name), expected_segment
  end

  def test_promises_future_creates_segments_for_nested_instrumented_calls
    with_config(:'instrumentation.thread.tracing' => false) do
      txn = concurrent_promises_calls_net_http_in_block

      assert_equal(3, txn.segments.length)
      assert_expected_segments_in_transaction(txn)
    end
  end

  def test_promises_future_creates_segments_for_nested_instrumented_calls_with_thread_tracing_enabled
    with_config(:'instrumentation.thread.tracing' => true) do
      txn = concurrent_promises_calls_net_http_in_block

      # We can't check the number of segments when thread tracing is enabled because we cannot rely on concurrent-ruby
      # creating threads during this transaction, as it can reuse threads that were created previously.
      # Instead, we check to make sure the segments that should be present are.
      assert_expected_segments_in_transaction(txn)
    end
  end

  def test_promises_future_captures_segment_error
    txn = in_transaction do
      # TODO: OLD RUBIES - RUBY_VERSION 2.2
      # specific "begin" in block can be removed once we drop support for 2.2
      begin
        simulate_error
      rescue StandardError => e
        # NOOP -- allowing span to notice error
      end
    end

    assert_segment_noticed_simulated_error(txn)
  end

  def test_noticed_error_at_segment_and_txn_on_error
    txn = nil
    begin
      in_transaction do |test_txn|
        txn = test_txn
        simulate_error
      end
    rescue StandardError => e
      # NOOP -- allowing span and transaction to notice error
    end

    assert_segment_noticed_simulated_error(txn)
    assert_transaction_noticed_error txn, /RuntimeError/
  end

  def test_task_segment_has_correct_parent
    txn = future_in_transaction { 'are you my mother?' }
    task_segment = txn.segments.find { |n| n.name == 'Concurrent/Task' }

    assert_equal task_segment.parent.name, txn.best_name
  end

  def test_segment_not_created_if_tracing_disabled
    NewRelic::Agent::Tracer.stub :tracing_enabled?, false do
      txn = future_in_transaction { 'the revolution will not be televised' }

      assert_predicate txn.segments, :one?
      assert_equal txn.segments.first.name, txn.best_name
    end
  end

  def test_supportability_metric_recorded_once
    in_transaction do
      Concurrent::Promises.future { 'one-banana' }
    end

    in_transaction do
      Concurrent::Promises.future { 'two-banana' }
    end

    assert_metrics_recorded(NewRelic::Agent::Instrumentation::ConcurrentRuby::SUPPORTABILITY_METRIC)
  end
end
