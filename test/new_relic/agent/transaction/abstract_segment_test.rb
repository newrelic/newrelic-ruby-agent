# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

require 'new_relic/agent/transaction'
require 'new_relic/agent/transaction/abstract_segment'

module NewRelic
  module Agent
    class Transaction
      class AbstractSegmentTest < Minitest::Test
        class BasicSegment < AbstractSegment
        end

        def setup
          freeze_time
        end

        def test_segment_is_nameable
          segment = BasicSegment.new  "Custom/basic/segment"
          assert_equal "Custom/basic/segment", segment.name
        end

        def test_segment_tracks_timing_information
          segment = BasicSegment.new "Custom/basic/segment"
          segment.start
          assert_equal Time.now, segment.start_time

          advance_time 1.0
          segment.finish

          assert_equal Time.now, segment.end_time
          assert_equal 1.0, segment.duration
          assert_equal 1.0, segment.exclusive_duration
        end
      end
    end
  end
end
