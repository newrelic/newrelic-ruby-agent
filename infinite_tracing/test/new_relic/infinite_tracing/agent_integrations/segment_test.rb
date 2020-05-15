# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

require File.expand_path('../../../../test_helper', __FILE__)

module NewRelic
  module Agent
    module InfiniteTracing
      class SegmentIntegrationTest < Minitest::Test
        include FakeTraceObserverHelpers

        def test_sampled_segment_records_span_event
          trace_id  = nil
          txn_guid  = nil
          sampled   = nil
          priority  = nil
          timestamp = nil

          span_events = generate_and_stream_segments do
            in_transaction('wat') do |txn|
              txn.stubs(:sampled?).returns(true)

              segment = Transaction::Segment.new 'Ummm'
              txn.add_segment segment
              segment.start
              advance_time 1.0
              segment.finish

              timestamp = Integer(segment.start_time.to_f * 1000.0)

              trace_id = txn.trace_id
              txn_guid = txn.guid
              sampled  = txn.sampled?
              priority = txn.priority
            end
          end

          assert_equal 2, span_events.size

          custom_span_event = span_events[0]
          root_span_event   = span_events[1]
          root_guid         = root_span_event['intrinsics']['guid'].string_value

          assert_equal 'Span',    custom_span_event['intrinsics']['type'].string_value
          assert_equal trace_id,  custom_span_event['intrinsics']['traceId'].string_value
          refute                  custom_span_event['intrinsics']['guid'].string_value.empty?
          assert_equal root_guid, custom_span_event['intrinsics']['parentId'].string_value
          assert_equal txn_guid,  custom_span_event['intrinsics']['transactionId'].string_value
          assert_equal sampled,   custom_span_event['intrinsics']['sampled'].bool_value
          assert_equal priority,  custom_span_event['intrinsics']['priority'].double_value
          assert_equal timestamp, custom_span_event['intrinsics']['timestamp'].int_value
          assert_equal 1.0,       custom_span_event['intrinsics']['duration'].double_value
          assert_equal 'Ummm',    custom_span_event['intrinsics']['name'].string_value
          assert_equal 'generic', custom_span_event['intrinsics']['category'].string_value
        end

        def test_non_sampled_segment_does_record_span_event
          span_events = generate_and_stream_segments do
            in_transaction('wat') do |txn|
              txn.stubs(:sampled?).returns(false)

              segment = Transaction::Segment.new 'Ummm'
              txn.add_segment segment
              segment.start
              advance_time 1.0
              segment.finish
            end
          end

          assert_equal 2, span_events.size
        end

        def test_streams_multiple_segments
          total_spans = 5
          segments = []
        
          span_events = generate_and_stream_segments do
            total_spans.times do |index|
              with_segment do |segment|
                segments << segment
              end
            end
          end
      
          assert_equal total_spans, span_events.size
          assert_equal total_spans, segments.size
        end
      end
    end
  end
end
