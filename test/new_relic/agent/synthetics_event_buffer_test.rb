# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'test/new_relic/agent/event_buffer_test_cases'
require 'new_relic/agent/synthetics_event_buffer'

module NewRelic::Agent
  class SyntheticsEventBufferTest < Minitest::Test
    include EventBufferTestCases

    def buffer_class
      SyntheticsEventBuffer
    end

    def create_event(timestamp)
      [{"timestamp" => timestamp}, {}]
    end

    def test_append_with_reject_returns_rejected_item
      buffer = buffer_class.new(5)

      5.times do |i|
        result, reject = buffer.append_with_reject(create_event(i))
        refute_nil(result)
        assert_nil(reject)
      end

      event = create_event(10)
      result, reject = buffer.append_with_reject(event)

      assert_nil result
      assert_equal event, reject
    end

    def test_append_with_reject_bases_removal_on_timestamp
      buffer = buffer_class.new(5)

      last_event = nil
      5.times do |i|
        last_event = create_event(i + 10)
        result = buffer.append(last_event)
        assert(result)
      end

      event = create_event(1)
      result, reject = buffer.append_with_reject(event)

      assert_equal event, result
      assert_equal last_event, reject
    end
  end
end
