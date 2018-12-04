# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../../test_helper', __FILE__)
require 'new_relic/agent/instrumentation/active_storage_subscriber'
require 'securerandom'

module NewRelic
  module Agent
    module Instrumentation
      class ActiveStorageSubscriberTest < Minitest::Test
        def setup
          nr_freeze_time
          @subscriber = ActiveStorageSubscriber.new
          @id = SecureRandom.hex

          NewRelic::Agent.drop_buffered_data
        end

        def teardown
          NewRelic::Agent.drop_buffered_data
        end

        def test_metrics_recorded_for_known_methods
          in_transaction 'test' do
            @subscriber.class::METHOD_NAME_MAPPING.each do |event_name, _|
              generate_event event_name
            end
          end

          @subscriber.class::METHOD_NAME_MAPPING.each do |_, method_name|
            assert_metrics_recorded "Ruby/ActiveStorage/DiskService/#{method_name}"
          end
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

        private

        def generate_event(event_name, attributes = {})
          defaults = {key: SecureRandom.hex, service: "Disk"}
          payload = defaults.merge(attributes)
          @subscriber.start event_name, @id, payload
          yield if block_given?
          @subscriber.finish event_name, @id, payload
        end
      end
    end
  end
end
