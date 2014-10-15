# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'test/new_relic/agent/event_buffer_test_cases'
require 'new_relic/agent/sized_buffer'

module NewRelic::Agent
  class SizedBufferTest < Minitest::Test
    include EventBufferTestCases

    def buffer_class
      SizedBuffer
    end

    def test_append_returns_whether_item_was_stored
      buffer = buffer_class.new(5)

      5.times do |i|
        result = buffer.append(i)
        assert(result)
      end

      result = buffer.append('foo')
      refute(result)
    end
  end
end
