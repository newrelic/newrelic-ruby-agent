# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
require File.expand_path '../../../../../test_helper', __FILE__

module NewRelic
  module Agent
    module Instrumentation
      class ActiveStorageSubscriberTest < Minitest::Test
        def setup
          nr_freeze_process_time
          @subscriber = ActiveStorageSubscriber.new
          @id = fake_guid(32)

          NewRelic::Agent.drop_buffered_data
        end

        def teardown
          NewRelic::Agent.drop_buffered_data
        end

        def test_metrics_recorded_for_known_methods
          method_name_mapping = {
            "service_upload.active_storage" => "upload".freeze,
            "service_streaming_download.active_storage" => "streaming_download".freeze,
            "service_download.active_storage" => "download".freeze,
            "service_delete.active_storage" => "delete".freeze,
            "service_delete_prefixed.active_storage" => "delete_prefixed".freeze,
            "service_exist.active_storage" => "exist".freeze,
            "service_url.active_storage" => "url".freeze
          }

          in_transaction 'test' do
            method_name_mapping.keys.each do |event_name|
              generate_event event_name
            end
          end

          method_name_mapping.values.each do |method_name|
            assert_metrics_recorded "Ruby/ActiveStorage/DiskService/#{method_name}"
          end
        end

        def test_metric_will_recorded_for_new_event_names
          in_transaction 'test' do
            generate_event 'service_new_method.active_storage'
          end

          assert_metrics_recorded 'Ruby/ActiveStorage/DiskService/new_method'
        end

        def test_failsafe_if_event_does_not_match_expected_pattern
          in_transaction 'test' do
            generate_event 'wat?'
          end

          assert_metrics_recorded 'Ruby/ActiveStorage/DiskService/unknown'
        end

        def test_key_recorded_as_attribute_on_traces
          in_transaction 'test' do
            generate_event 'service_upload.active_storage', key: 'mykey'
          end

          trace = last_transaction_trace
          tt_node = find_node_with_name(trace, "Ruby/ActiveStorage/DiskService/upload")

          assert_equal 'mykey', tt_node.params[:key]
        end

        def test_exist_recorded_as_attribute_on_traces
          in_transaction 'test' do
            generate_event 'service_exist.active_storage', exist: false
          end

          trace = last_transaction_trace
          tt_node = find_node_with_name(trace, "Ruby/ActiveStorage/DiskService/exist")

          assert tt_node.params.key? :exist
          assert_equal false, tt_node.params[:exist]
        end

        def test_segment_created
          in_transaction 'test' do
            txn = NewRelic::Agent::Tracer.current_transaction
            assert_equal 1, txn.segments.size

            generate_event 'service_exist.active_storage', exist: false
            assert_equal 2, txn.segments.size
            assert_equal 'Ruby/ActiveStorage/DiskService/exist', txn.segments.last.name
            assert txn.segments.last.finished?, "Segment #{txn.segments.last.name} was never finished.  "
          end
        end

        def test_records_span_level_error
          exception_class = StandardError
          exception_msg = "Natural 1"
          exception = exception_class.new(msg = exception_msg)
          # :exception_object was added in Rails 5 and above
          params = {:exception_object => exception, :exception => [exception_class.name, exception_msg]}

          txn = nil

          in_transaction do |test_txn|
            txn = test_txn
            generate_event 'service_upload.active_storage', params
          end

          assert_segment_noticed_error txn, /upload/i, exception_class.name, /Natural 1/i
        end

        private

        def generate_event(event_name, attributes = {})
          defaults = {key: fake_guid(32), service: "Disk"}
          payload = defaults.merge(attributes)
          @subscriber.start event_name, @id, payload
          yield if block_given?
          @subscriber.finish event_name, @id, payload
        end
      end
    end
  end
end
