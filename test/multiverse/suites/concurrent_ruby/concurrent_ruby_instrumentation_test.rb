# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class ConcurrentRubyInstrumentationTest < Minitest::Test
  def test_promises_future_creates_segment_with_default_name
    txn = in_transaction do
      Concurrent::Promises.future { 'hi' }
    end
    segment = txn.segments[1]

    assert_equal segment.name, NewRelic::Agent::Instrumentation::ConcurrentRuby::DEFAULT_NAME
  end

  def test_promises_future_creates_segments_for_nested_instrumented_calls
    future = nil
    txn = in_transaction do
      future = Concurrent::Promises.future { Net::HTTP.get(URI('http://www.example.com')) }
    end

    assert_equal(3, txn.segments.length)
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