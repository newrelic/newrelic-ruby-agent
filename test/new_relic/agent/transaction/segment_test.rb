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
          @additional_config = { :'distributed_tracing.enabled' => true }
          NewRelic::Agent.config.add_config_for_testing(@additional_config)
          NewRelic::Agent.config.notify_server_source_added
          nr_freeze_time
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
          test_segment, err = capture_segment_with_error
          current_noticed_error = test_segment.noticed_error

          assert current_noticed_error, "expected noticed_error to not be nil"

          test_segment.noticed_error.build_error_attributes
          attributes = test_segment.noticed_error_attributes
          assert attributes, "expected noticed_error_attributes to not be nil"

          refute_empty attributes
          assert_equal "oops!", attributes["error.message"]
          assert_equal "RuntimeError", attributes["error.class"]

          # segment tagging should preserve current noticed error!
          test_segment.notice_error err
          assert current_noticed_error.equal?(test_segment.noticed_error), 
            "did not expect a new instance of noticed_error"
        end

        def test_segment_with_no_error_does_not_produce_error_attributes
          segment, _ = with_segment do |segment|
            # A perfectly fine walk through segmentland
          end
          refute segment.noticed_error_attributes
        end

        def test_segment_has_error_attributes_after_error
          segment, error = capture_segment_with_error
          refute_empty segment.noticed_error_attributes
        end

        def test_nested_segment_has_error_attributes_after_error
          nested_segment, parent_segment, error = capture_nested_segment_with_error
          refute parent_segment.noticed_error_attributes
          refute_empty nested_segment.noticed_error_attributes
        end

        def test_ignores_error_attributes_when_in_high_security
          with_config(:high_security => true) do
            segment, error = capture_segment_with_error
            assert_empty attributes_for(segment, :agent)
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
          segment = Segment.new  "Custom/simple/segment", "Segment/all"
          assert_equal "Custom/simple/segment", segment.name
          assert_equal "Segment/all", segment.unscoped_metrics
        end

        def test_assigns_unscoped_metrics_as_array
          segment = Segment.new  "Custom/simple/segment", ["Segment/all", "Other/all"]
          assert_equal "Custom/simple/segment", segment.name
          assert_equal ["Segment/all", "Other/all"], segment.unscoped_metrics
        end

        def test_segment_does_not_record_metrics_outside_of_txn
          segment = Segment.new  "Custom/simple/segment", "Segment/all"
          segment.start
          advance_time 1.0
          segment.finish

          refute_metrics_recorded ["Custom/simple/segment", "Segment/all"]
        end

        def test_segment_records_metrics
          in_transaction "test" do |txn|
            segment = Segment.new  "Custom/simple/segment", "Segment/all"
            txn.add_segment segment
            segment.start
            advance_time 1.0
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
            "DurationByCaller/Unknown/Unknown/Unknown/Unknown/allOther",
          ]
        end

        def test_segment_records_metrics_when_given_as_array
          in_transaction do |txn|
            segment = Segment.new  "Custom/simple/segment", ["Segment/all", "Other/all"]
            txn.add_segment segment
            segment.start
            advance_time 1.0
            segment.finish
          end

          assert_metrics_recorded ["Custom/simple/segment", "Segment/all", "Other/all"]
        end

        def test_segment_can_disable_scoped_metric_recording
          in_transaction('test') do |txn|
            segment = Segment.new  "Custom/simple/segment", "Segment/all"
            segment.record_scoped_metric = false
            txn.add_segment segment
            segment.start
            advance_time 1.0
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
            "DurationByCaller/Unknown/Unknown/Unknown/Unknown/allOther",
          ]
        end

        def test_segment_can_disable_scoped_metric_recording_with_unscoped_as_frozen_array
          in_transaction('test') do |txn|
            segment = Segment.new  "Custom/simple/segment", ["Segment/all", "Segment/allOther"].freeze
            segment.record_scoped_metric = false
            txn.add_segment segment
            segment.start
            advance_time 1.0
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
            "DurationByCaller/Unknown/Unknown/Unknown/Unknown/allOther",
          ]
        end

        def test_non_sampled_segment_does_not_record_span_event
          in_transaction('wat') do |txn|
            txn.stubs(:sampled?).returns(false)

            segment = Segment.new 'Ummm'
            txn.add_segment segment
            segment.start
            advance_time 1.0
            segment.finish
          end

          last_span_events = NewRelic::Agent.agent.span_event_aggregator.harvest![1]
          assert_empty last_span_events
        end

        def test_sampled_segment_records_span_event
          trace_id  = nil
          txn_guid  = nil
          sampled   = nil
          priority  = nil
          timestamp = nil

          in_transaction('wat') do |txn|
            txn.stubs(:sampled?).returns(true)

            segment = Segment.new 'Ummm'
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

          last_span_events  = NewRelic::Agent.agent.span_event_aggregator.harvest![1]
          assert_equal 2, last_span_events.size
          custom_span_event = last_span_events[0][0]
          root_span_event   = last_span_events[1][0]
          root_guid         = root_span_event['guid']

          assert_equal 'Span',    custom_span_event.fetch('type')
          assert_equal trace_id,  custom_span_event.fetch('traceId')
          refute_nil              custom_span_event.fetch('guid')
          assert_equal root_guid, custom_span_event.fetch('parentId')
          assert_equal txn_guid,  custom_span_event.fetch('transactionId')
          assert_equal sampled,   custom_span_event.fetch('sampled')
          assert_equal priority,  custom_span_event.fetch('priority')
          assert_equal timestamp, custom_span_event.fetch('timestamp')
          assert_equal 1.0,       custom_span_event.fetch('duration')
          assert_equal 'Ummm',    custom_span_event.fetch('name')
          assert_equal 'generic', custom_span_event.fetch('category')
        end

        def test_sets_start_time_from_constructor
          t = Time.now
          segment = Segment.new nil, nil, t
          assert_equal t, segment.start_time
        end

        def test_generates_guid_when_running_out_of_file_descriptors
          # SecureRandom.hex raises an exception when the ruby interpreter
          # uses up all of its allotted file descriptors.
          # See also: https://github.com/newrelic/rpm/issues/303
          file_descriptors = []
          begin
            # Errno::EMFILE is raised when the system runs out of file
            # descriptors
            # If the segment constructor fails to create a random guid, the
            # exception would be a RuntimeError
            assert_raises Errno::EMFILE do
              while true do
                file_descriptors << IO.sysopen(__FILE__)
                Segment.new "Test #{file_descriptors[-1]}"
              end
            end
          ensure
            file_descriptors.map { |fd| IO::new(fd).close }
          end
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
            build_deferred_error_attributes segment_with_error
            refute_equal parent_segment, segment_with_error
            return segment_with_error, parent_segment, exception
          end
        end

      end
    end
  end
end
