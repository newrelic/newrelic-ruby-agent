# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class ConcurrentRubyInstrumentationTest < Minitest::Test
  EXPECTED_SEGMENTS_FOR_NESTED_CALLS = [
    'Concurrent::ThreadPoolExecutor#post',
    'Concurrent/task',
    'External/www.example.com/Net::HTTP/GET'
  ]

  def concurrent_promises_calls_net_http_in_block
    in_transaction do
      future = Concurrent::Promises.future { Net::HTTP.get(URI('http://www.example.com')); }
      future.wait!
    end
  end

  def test_promises_future_creates_segment_with_default_name
    txn = in_transaction do
      future = Concurrent::Promises.future { 'hi' }
      future.wait!
    end

    expected_segments = ['Concurrent::ThreadPoolExecutor#post', 'Concurrent/task']

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
    txn = nil
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

    assert_segment_noticed_error txn, /Concurrent\/task/, /RuntimeError/, /hi/i
  end
end
