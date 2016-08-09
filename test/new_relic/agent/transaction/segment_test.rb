# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

require 'new_relic/agent/transaction/segment'

module NewRelic
  module Agent
    class Transaction
      class SegmentTest < Minitest::Test
        def setup
          freeze_time
        end

        def teardown
          NewRelic::Agent.drop_buffered_data
        end

        def test_assigns_unscoped_metrics
          segment = Segment.new  "Custom/simple/segment", "Segment/all"
          assert_equal "Custom/simple/segment", segment.name
          assert_equal "Segment/all", segment.unscoped_metrics
        end

        def test_assigns_unscoped_metrics_as_array
          segment = Segment.new  "Custom/simple/segment", ["Segment/all", "Other/all"]
          assert_equal "Custom/simple/segment", segment.name
          assert_equal ["Segment/all", "Other/all"], segment.unscoped_metrics
        end

        def test_segment_records_metrics
          segment = Segment.new  "Custom/simple/segment", "Segment/all"
          segment.start
          advance_time 1.0
          segment.finish

          assert_metrics_recorded ["Custom/simple/segment", "Segment/all"]
        end

        def test_segment_records_metrics_when_given_as_array
          segment = Segment.new  "Custom/simple/segment", ["Segment/all", "Other/all"]
          segment.start
          advance_time 1.0
          segment.finish

          assert_metrics_recorded ["Custom/simple/segment", "Segment/all", "Other/all"]
        end
      end
    end
  end
end
