# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require File.expand_path('../../../test_helper', __FILE__)

module NewRelic
  module Agent
    module InfiniteTracing
      class ExternalRequestSegmentIntegrationTest < Minitest::Test
        include FakeTraceObserverHelpers

        def test_sampled_external_records_span_event
          trace_id  = nil
          txn_guid  = nil
          sampled   = nil
          priority  = nil
          timestamp = nil
          segment   = nil

          span_events = generate_and_stream_segments do
            in_transaction('wat') do |txn|
              txn.stubs(:sampled?).returns(true)

              segment = Transaction::ExternalRequestSegment.new \
                "Typhoeus",
                "http://remotehost.com/blogs/index",
                "GET"

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
          external_intrinsics       = span_events[0]['intrinsics']
          external_agent_attributes = span_events[0]['agent_attributes']
          root_span_event           = span_events[1]['intrinsics']
          root_guid                 = root_span_event['guid'].string_value

          expected_name = 'External/remotehost.com/Typhoeus/GET'

          assert_equal 'Span',            external_intrinsics['type'].string_value
          assert_equal trace_id,          external_intrinsics['traceId'].string_value
          refute_nil                      external_intrinsics['guid'].string_value
          assert_equal root_guid,         external_intrinsics['parentId'].string_value
          assert_equal txn_guid,          external_intrinsics['transactionId'].string_value
          assert_equal sampled,           external_intrinsics['sampled'].bool_value
          assert_equal priority,          external_intrinsics['priority'].double_value
          assert_equal timestamp,         external_intrinsics['timestamp'].int_value
          assert_equal 1.0,               external_intrinsics['duration'].double_value
          assert_equal expected_name,     external_intrinsics['name'].string_value
          assert_equal segment.library,   external_intrinsics['component'].string_value
          assert_equal segment.procedure, external_intrinsics['http.method'].string_value
          assert_equal 'http',            external_intrinsics['category'].string_value
          assert_equal segment.uri.to_s,  external_agent_attributes['http.url'].string_value
        end

        def test_non_sampled_segment_does_record_span_event
          span_events = generate_and_stream_segments do
            in_transaction('wat') do |txn|
              txn.stubs(:sampled?).returns(false)

              segment = Transaction::ExternalRequestSegment.new \
                "Typhoeus",
                 "http://remotehost.com/blogs/index",
                 "GET"

              txn.add_segment segment
              segment.start
              advance_time 1.0
              segment.finish
            end
          end

          assert_equal 2, span_events.size
        end

      end
    end
  end
end
