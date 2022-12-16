# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class ConcurrentRubyInstrumentationTest < Minitest::Test
  def test_promises_future_creates_segment_with_default_name
    skip
    txn = in_transaction do
      Concurrent::Promises.future { 'hi' }
    end
    segment = txn.segments[1]

    assert_equal segment.name, NewRelic::Agent::Instrumentation::ConcurrentRuby::DEFAULT_NAME
  end

  def test_promises_future_creates_segments_for_nested_instrumented_calls
    skip
    with_config(:'instrumentation.thread.tracing' => false) do
      future = nil
      txn = in_transaction do
        future = Concurrent::Promises.future { Net::HTTP.get(URI('http://www.example.com')); }
        future.wait!
      end

      assert_equal(4, txn.segments.length)
    end
  end

  def test_promises_future_creates_segments_for_nested_instrumented_calls_with_thread_tracing_enabled
    # skip
    with_config(:'instrumentation.thread.tracing' => true) do
      future = nil
      txn = in_transaction do
        future = Concurrent::Promises.future { Net::HTTP.get(URI('http://www.example.com')); }
        future.wait!
      end

      # intermittent failure with thread segment missing?  idk why yet
      #   dummy
      #   Concurrent::ThreadPoolExecutor#post
      #   Ruby/Thread/2640
      #   Ruby/Inner_concurrent_ruby/2640
      #   External/www.example.com/Net::HTTP/GET
      txn.segments.each do |s|
        puts s.name
      end

      assert_equal(5, txn.segments.length)
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
    skip "future doesn't raise errors, so they can't be captured"
    txn = nil
    txn = in_transaction('concurrent') do
      Concurrent::Promises.stub(:future, raise('boom!')) do
        future = Concurrent::Promises.future { 'hi' }
      end
    rescue StandardError => e
      # NOOP -- allowing span and transaction to notice error
    end

    assert_segment_noticed_error txn, /concurrent$/, StandardError, /boom/i
    assert_transaction_noticed_error txn, StandardError
  end
end
