# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'
require 'new_relic/agent/transaction/segment'

module NewRelic
  module Agent
    class Transaction
      class SegmentTest < Minitest::Test
        def setup
          @additional_config = {:'distributed_tracing.enabled' => true}
          NewRelic::Agent.config.add_config_for_testing(@additional_config)
          NewRelic::Agent.config.notify_server_source_added
          nr_freeze_process_time
        end

        def teardown
          NewRelic::Agent.config.remove_config(@additional_config)
          reset_buffers_and_caches
        end

        def test_logs_warning_if_a_non_hash_arg_is_passed_to_add_custom_span_attributes
          expects_logging(:warn, includes("add_custom_span_attributes"))
          in_transaction do
            NewRelic::Agent.add_custom_span_attributes('fooz')
          end
        end

        def test_ignores_custom_attributes_when_in_high_security
          with_config(:high_security => true) do
            with_segment do |segment|
              NewRelic::Agent.add_custom_span_attributes(:failure => "is an option")
              assert_empty attributes_for(segment, :custom)
            end
          end
        end

        def test_records_error_attributes_on_segment
          test_segment, _error = capture_segment_with_error
          current_noticed_error = test_segment.noticed_error

          assert current_noticed_error, "expected noticed_error to not be nil"

          test_segment.noticed_error.build_error_attributes
          attributes = test_segment.noticed_error_attributes
          assert attributes, "expected noticed_error_attributes to not be nil"

          refute_empty attributes
          assert_equal "oops!", attributes["error.message"]
          assert_equal "RuntimeError", attributes["error.class"]
        end

        def test_segment_with_no_error_does_not_produce_error_attributes
          segment, _ = with_segment do
            # A perfectly fine walk through segmentland
          end
          refute segment.noticed_error_attributes
        end

        def test_segment_has_error_attributes_after_error
          segment, _error = capture_segment_with_error
          refute_empty segment.noticed_error_attributes
        end

        def test_nested_segment_has_error_attributes_after_error
          nested_segment, parent_segment, _error = capture_nested_segment_with_error
          refute parent_segment.noticed_error_attributes
          refute_empty nested_segment.noticed_error_attributes
        end

        def test_ignores_error_attributes_when_in_high_security
          with_config(:high_security => true) do
            segment, _error = capture_segment_with_error
            agent_attributes = attributes_for(segment, :agent)

            # No error attributes
            assert_equal({"parent.transportType" => "Unknown"}, agent_attributes)
          end
        end

        def test_adding_custom_attributes
          with_config(:'span_events.attributes.enabled' => true) do
            with_segment do |segment|
              NewRelic::Agent.add_custom_span_attributes(:foo => "bar")
              actual = segment.attributes.custom_attributes_for(NewRelic::Agent::AttributeFilter::DST_SPAN_EVENTS)
              assert_equal({"foo" => "bar"}, actual)
            end
          end
        end

        def test_assigns_unscoped_metrics
          segment = Segment.new("Custom/simple/segment", "Segment/all")
          assert_equal "Custom/simple/segment", segment.name
          assert_equal "Segment/all", segment.unscoped_metrics
        end

        def test_assigns_unscoped_metrics_as_array
          segment = Segment.new("Custom/simple/segment", ["Segment/all", "Other/all"])
          assert_equal "Custom/simple/segment", segment.name
          assert_equal ["Segment/all", "Other/all"], segment.unscoped_metrics
        end

        def test_segment_does_not_record_metrics_outside_of_txn
          segment = Segment.new("Custom/simple/segment", "Segment/all")
          segment.start
          advance_process_time(1.0)
          segment.finish

          refute_metrics_recorded ["Custom/simple/segment", "Segment/all"]
        end

        def test_segment_records_metrics
          in_transaction("test") do |txn|
            segment = Segment.new("Custom/simple/segment", "Segment/all")
            txn.add_segment(segment)
            segment.start
            advance_process_time(1.0)
            segment.finish
          end

          assert_metrics_recorded [
            "test",
            ["Custom/simple/segment", "test"],
            "Custom/simple/segment",
            "Segment/all",
            "OtherTransactionTotalTime",
            "OtherTransactionTotalTime/test",
            "DurationByCaller/Unknown/Unknown/Unknown/Unknown/all",
            "Supportability/API/recording_web_transaction?",
            "DurationByCaller/Unknown/Unknown/Unknown/Unknown/allOther"
          ]
        end

        def test_segment_records_metrics_when_given_as_array
          in_transaction do |txn|
            segment = Segment.new("Custom/simple/segment", ["Segment/all", "Other/all"])
            txn.add_segment(segment)
            segment.start
            advance_process_time(1.0)
            segment.finish
          end

          assert_metrics_recorded ["Custom/simple/segment", "Segment/all", "Other/all"]
        end

        def test_segment_can_disable_scoped_metric_recording
          in_transaction('test') do |txn|
            segment = Segment.new("Custom/simple/segment", "Segment/all")
            segment.record_scoped_metric = false
            txn.add_segment(segment)
            segment.start
            advance_process_time(1.0)
            segment.finish
          end

          assert_metrics_recorded_exclusive [
            "test",
            "Custom/simple/segment",
            "Segment/all",
            "Supportability/API/drop_buffered_data",
            "OtherTransactionTotalTime",
            "OtherTransactionTotalTime/test",
            "DurationByCaller/Unknown/Unknown/Unknown/Unknown/all",
            "Supportability/API/recording_web_transaction?",
            "DurationByCaller/Unknown/Unknown/Unknown/Unknown/allOther"
          ], :ignore_filter => %r{^(Supportability/Logging|Supportability/API)}
        end

        def test_segment_can_disable_scoped_metric_recording_with_unscoped_as_frozen_array
          in_transaction('test') do |txn|
            segment = Segment.new("Custom/simple/segment", ["Segment/all", "Segment/allOther"].freeze)
            segment.record_scoped_metric = false
            txn.add_segment(segment)
            segment.start
            advance_process_time(1.0)
            segment.finish
          end

          assert_metrics_recorded [
            "test",
            "Custom/simple/segment",
            "Segment/all",
            "Segment/allOther",
            "OtherTransactionTotalTime",
            "OtherTransactionTotalTime/test",
            "DurationByCaller/Unknown/Unknown/Unknown/Unknown/all",
            "Supportability/API/recording_web_transaction?",
            "DurationByCaller/Unknown/Unknown/Unknown/Unknown/allOther"
          ]
        end

        def test_non_sampled_segment_does_not_record_span_event
          in_transaction('wat') do |txn|
            txn.stubs(:sampled?).returns(false)

            segment = Segment.new('Ummm')
            txn.add_segment(segment)
            segment.start
            advance_process_time(1.0)
            segment.finish
          end

          last_span_events = NewRelic::Agent.agent.span_event_aggregator.harvest![1]
          assert_empty last_span_events
        end

        def test_ignored_transaction_does_not_record_span_events
          in_transaction('wat') do |txn|
            txn.stubs(:ignore?).returns(true)

            segment = Segment.new('Ummm')
            txn.add_segment(segment)
            segment.start
            advance_process_time(1.0)
            segment.finish
          end

          last_span_events = NewRelic::Agent.agent.span_event_aggregator.harvest![1]
          assert_empty last_span_events
        end

        def test_sampled_segment_records_span_event
          trace_id = nil
          txn_guid = nil
          sampled = nil
          priority = nil
          timestamp = nil

          in_transaction('wat') do |txn|
            txn.stubs(:sampled?).returns(true)

            segment = Segment.new('Ummm')
            txn.add_segment(segment)
            segment.start
            advance_process_time(1.0)
            segment.finish

            timestamp = Integer(segment.start_time * 1000.0)

            trace_id = txn.trace_id
            txn_guid = txn.guid
            sampled = txn.sampled?
            priority = txn.priority
          end

          last_span_events = NewRelic::Agent.agent.span_event_aggregator.harvest![1]
          assert_equal 2, last_span_events.size
          custom_span_event = last_span_events[0][0]
          root_span_event = last_span_events[1][0]
          root_guid = root_span_event['guid']

          assert_equal 'Span', custom_span_event.fetch('type')
          assert_equal trace_id, custom_span_event.fetch('traceId')
          refute_nil custom_span_event.fetch('guid')
          assert_equal root_guid, custom_span_event.fetch('parentId')
          assert_equal txn_guid, custom_span_event.fetch('transactionId')
          assert_equal sampled, custom_span_event.fetch('sampled')
          assert_equal priority, custom_span_event.fetch('priority')
          assert_equal timestamp, custom_span_event.fetch('timestamp')
          assert_equal 1.0, custom_span_event.fetch('duration')
          assert_equal 'Ummm', custom_span_event.fetch('name')
          assert_equal 'generic', custom_span_event.fetch('category')
        end

        def test_sets_start_time_from_constructor
          t = Process.clock_gettime(Process::CLOCK_REALTIME)
          segment = Segment.new(nil, nil, t)
          assert_equal t, segment.start_time
        end

        def test_adding_agent_attributes
          in_transaction do |txn|
            txn.add_agent_attribute(:foo, "bar", AttributeFilter::DST_ALL)
            segment = NewRelic::Agent::Tracer.current_segment
            actual = segment.attributes.agent_attributes_for(AttributeFilter::DST_SPAN_EVENTS)
            assert_equal({:foo => "bar"}, actual)
          end
        end

        def test_request_attributes_in_agent_attributes
          request_attributes = {
            :referer => "/referred",
            :path => "/",
            :content_length => 0,
            :content_type => "application/json",
            :host => "foo.foo",
            :user_agent => "Use This!",
            :request_method => "GET"
          }
          request = stub("request", request_attributes)
          txn = in_transaction(:request => request) do
          end

          segment = txn.segments[0]
          actual = segment.attributes.agent_attributes_for(AttributeFilter::DST_SPAN_EVENTS)

          assert_equal "/referred", actual[:'request.headers.referer']
          assert_equal "/", actual[:'request.uri']
          assert_equal 0, actual[:'request.headers.contentLength']
          assert_equal "application/json", actual[:"request.headers.contentType"]
          assert_equal "foo.foo", actual[:'request.headers.host']
          assert_equal "Use This!", actual[:'request.headers.userAgent']
          assert_equal "GET", actual[:'request.method']
        end

        def test_transaction_response_attributes_included_in_agent_attributes
          txn = in_transaction do |t|
            t.http_response_code = 418
            t.response_content_length = 100
            t.response_content_type = 'application/json'
          end

          segment = txn.segments[0]
          actual = segment.attributes.agent_attributes_for(AttributeFilter::DST_SPAN_EVENTS)
          assert_equal 418, actual[:"http.statusCode"]
          assert_equal 100, actual[:"response.headers.contentLength"]
          assert_equal "application/json", actual[:"response.headers.contentType"]
        end

        def test_referer_in_agent_attributes
          segment = nil
          request = stub('request', :referer => "/referred", :path => "/")
          txn = in_transaction(:request => request) do
          end

          segment = txn.segments[0]
          actual = segment.attributes.agent_attributes_for(AttributeFilter::DST_SPAN_EVENTS)
          assert_equal "/referred", actual[:'request.headers.referer']
        end

        private

        # Similar to capture_segment_with_error, but we're capturing
        # a child/nested segment within which we raise an error
        def capture_nested_segment_with_error
          begin
            segment_with_error = nil
            parent_segment = nil
            with_segment do |segment|
              parent_segment = segment
              segment_with_error = Tracer.start_segment(name: "nested_test", parent: segment)
              raise "oops!"
            end
          rescue Exception => exception
            segment_with_error.finish
            assert segment_with_error, "expected to have a segment_with_error"
            build_deferred_error_attributes(segment_with_error)
            refute_equal parent_segment, segment_with_error
            return segment_with_error, parent_segment, exception
          end
        end
      end
    end
  end
end
