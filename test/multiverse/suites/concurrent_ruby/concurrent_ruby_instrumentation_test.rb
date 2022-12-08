# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class ConcurrentRubyInstrumentationTest < Minitest::Test
  def test_promises_future_creates_segment_with_default_name
    txn = in_transaction do
      Concurrent::Promises.future { 'hi' }
    end
    segment = txn.segments[1]

    assert_equal segment.name, NewRelic::Agent::Instrumentation::ConcurrentRuby::PROMISES_FUTURE_NAME
  end

  def test_promises_future_creates_segment_with_custom_name
    name = 'my little pony'
    txn = in_transaction do
      Concurrent::Promises.future(nr_name: name) { 'hi' }
    end
    segment = txn.segments[1]

    assert_equal segment.name, name
  end

  # hmm -- i think I'm not understanding how errors work in this context
  # https://github.com/ruby-concurrency/concurrent-ruby/blob/master/docs-source/promises.in.md?plain=1#L81
  def test_promises_future_captures_segment_error
    skip
    txn = nil
    begin
      txn = in_transaction('concurrent') do
        Concurrent::Promises.future { raise 'boom!' }
      end
    rescue StandardError => e
      # NOOP -- allowing span and transaction to notice error
    end

    assert_segment_noticed_error txn, /concurrent$/, StandardError, /boom/i
    assert_transaction_noticed_error txn, StandardError
  end

  # Concurrent::ExecutorService#post

  def test_post_creates_a_segment
    skip

    txn = in_transaction do
      Concurrent::SimpleExecutorService.new.post('Significant wallaby') {}
    end

    assert_equal 2, txn.segments.size
    segment = txn.segments[1]
  end
end
