# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class ConcurrentRubyInstrumentationTest < Minitest::Test
  EXPECTED_SEGMENTS_FOR_NESTED_CALLS = [
    'Concurrent::ThreadPoolExecutor#post',
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

  # Tests
  def concurrent_promises_calls_net_http_in_block
    future_in_transaction { Net::HTTP.get(URI('http://www.example.com')) }
  end

  def test_promises_future_creates_segment_with_default_name
    txn = future_in_transaction { 'hi' }
    expected_segments = ['Concurrent::ThreadPoolExecutor#post', 'Concurrent/Task']

    assert_equal(3, txn.segments.length)
    assert expected_segments.to_set.subset?(txn.segments.map { |s| s.name }.to_set)
  end

  def test_promises_future_creates_segments_for_nested_instrumented_calls
    with_config(:'instrumentation.thread.tracing' => false) do
      txn = concurrent_promises_calls_net_http_in_block

      assert_equal(4, txn.segments.length)
      assert EXPECTED_SEGMENTS_FOR_NESTED_CALLS.to_set.subset?(txn.segments.map { |s| s.name }.to_set)
    end
  end

  def test_promises_future_creates_segments_for_nested_instrumented_calls_with_thread_tracing_enabled
    with_config(:'instrumentation.thread.tracing' => true) do
      txn = concurrent_promises_calls_net_http_in_block

      # We can't check the number of segments when thread tracing is enabled because we can not rely on concurrent
      # ruby creating threads during this transaction, as it can reuse threads that were created previously.
      # Instead, we check to make sure the segments that should be present are.
      assert EXPECTED_SEGMENTS_FOR_NESTED_CALLS.to_set.subset?(txn.segments.map { |s| s.name }.to_set)
    end
  end

  def test_promises_future_captures_segment_error
    txn = in_transaction do
      # TODO: OLD RUBIES - RUBY_VERSION 2.2
      # specific "begin" in block can be removed once we drop support for 2.2
      begin
        future = Concurrent::Promises.future { raise 'hi' }
        future.wait!
      rescue StandardError => e
        # NOOP -- allowing span and transaction to notice error
      end
    end

    assert_segment_noticed_error txn, /Concurrent\/Task/, /RuntimeError/, /hi/i
  end

  def test_task_segment_has_correct_parent
    txn = future_in_transaction { 'hi' }
    task_segment = txn.segments.find{|n| n.name == 'Concurrent/Task'}
    assert_equal task_segment.parent.name, txn.best_name
  end

  def test_segment_not_created_if_tracing_disabled
    NewRelic::Agent::Tracer.stub :tracing_enabled?, false do
      txn = future_in_transaction { 'the revolution will not be televised' }
      assert_predicate txn.segments, :one?
      assert_equal txn.segments.first.name, txn.best_name
    end
  end
end
