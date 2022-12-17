# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class ConcurrentRubyInstrumentationTest < Minitest::Test
  def test_promises_future_creates_segment_with_default_name
    skip
    txn = in_transaction do
      future = Concurrent::Promises.future { 'hi' }
      future.wait!
    end

    expected_segments = ['Concurrent::ThreadPoolExecutor#post', 'Concurrent/task']

    assert_equal(3, txn.segments.length)
    assert expected_segments.to_set.subset?(txn.segments.map { |s| s.name }.to_set)
  end

  def test_promises_future_creates_segments_for_nested_instrumented_calls
    skip
    with_config(:'instrumentation.thread.tracing' => false) do
      future = nil
      txn = in_transaction do
        future = Concurrent::Promises.future { Net::HTTP.get(URI('http://www.example.com')); }
        future.wait!
      end

      expected_segments = ['Concurrent::ThreadPoolExecutor#post', 'Concurrent/task', 'External/www.example.com/Net::HTTP/GET']

      assert_equal(4, txn.segments.length)
      assert expected_segments.to_set.subset?(txn.segments.map { |s| s.name }.to_set)
    end
  end

  def test_promises_future_creates_segments_for_nested_instrumented_calls_with_thread_tracing_enabled
    skip
    with_config(:'instrumentation.thread.tracing' => true) do
      future = nil
      txn = in_transaction do
        future = Concurrent::Promises.future { Net::HTTP.get(URI('http://www.example.com')); }
        future.wait!
      end

      expected_segments = ['Concurrent::ThreadPoolExecutor#post', 'Concurrent/task', 'External/www.example.com/Net::HTTP/GET']
      # We can't check the number of segments when thread tracing is enabled because we can not rely on concurrent
      # ruby creating threads during this transaction, as it can reuse threads that were created previously.
      # Instead, we check to make sure the segments that should be present are.
      assert expected_segments.to_set.subset?(txn.segments.map { |s| s.name }.to_set)
    end
  end

  # hmm -- i think I'm not understanding how errors work in this context
  # https://github.com/ruby-concurrency/concurrent-ruby/blob/master/docs-source/promises.in.md?plain=1#L81
  # Promises.future swallows all errors
  # they can be raised the result of the future as a variable and calling #value! on it
  # it also works if you call raise future
  # future.reason => inspect version of error
  # future.value => nil if there's an error
  # future.rejected? => true
  # future.value! => raises the error
  # raise future => raises the error
  # raise future rescue $! => rescues the error, returns inspected version

  def test_promises_future_captures_segment_error
    # skip "future doesn't raise errors, so they can't be captured"
    txn = nil
    txn = in_transaction('concurrent') do
      future = Concurrent::Promises.future { raise 'hi' }
      # future.reason
      future.wait!
    rescue StandardError => e
      # NOOP -- allowing span and transaction to notice error
    end

    # binding.irb

    assert_segment_noticed_error txn, /Concurrent\/task/, /RuntimeError/, /hi/i
  end
end
