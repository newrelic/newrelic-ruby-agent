# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/sized_buffer'

module NewRelic::Agent
  class SizedBufferTest < Minitest::Test
    def test_limits_itself_to_capacity
      buffer = SizedBuffer.new(10)

      11.times { |i| buffer.append(i) }

      assert_equal(10, buffer.to_a.size)
    end

    def test_append_increments_drop_count_when_over_capacity
      buffer = SizedBuffer.new(5)

      5.times { |i| buffer.append(i) }
      assert_equal(0, buffer.dropped)

      5.times { |i| buffer.append(i) }
      assert_equal(5, buffer.dropped)
    end

    def test_append_returns_whether_item_was_stored
      buffer = SizedBuffer.new(5)

      5.times do |i|
        result = buffer.append(i)
        assert(result)
      end

      result = buffer.append('foo')
      refute(result)
    end

    def test_to_a_returns_copy_of_samples_array
      buffer = SizedBuffer.new(5)

      5.times { |i| buffer.append(i) }

      items = buffer.to_a
      items << ['blarg']

      assert_equal([0,1,2,3,4], buffer.to_a)
    end

    def test_reset_resets_stored_items
      buffer = SizedBuffer.new(5)

      5.times { |i| buffer.append(i) }
      buffer.reset!

      assert_equal([], buffer.to_a)
    end

    def test_reset_resets_drop_count
      buffer = SizedBuffer.new(5)

      10.times { |i| buffer.append(i) }
      assert_equal(5, buffer.dropped)

      buffer.reset!
      assert_equal(0, buffer.dropped)
    end
  end
end
