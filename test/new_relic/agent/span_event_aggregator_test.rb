# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require File.expand_path('../../../test_helper', __FILE__)
require File.expand_path('../../data_container_tests', __FILE__)
require File.expand_path('../../common_aggregator_tests', __FILE__)
require 'new_relic/agent/span_event_aggregator'

module NewRelic
  module Agent
    class SpanEventAggregatorTest < Minitest::Test

      def setup
        @additional_config = { :'distributed_tracing.enabled' => true }
        NewRelic::Agent.config.add_config_for_testing(@additional_config)

        nr_freeze_time
        events = NewRelic::Agent.instance.events
        @event_aggregator = SpanEventAggregator.new events
      end

      def teardown
        NewRelic::Agent.config.remove_config(@additional_config)
        NewRelic::Agent.agent.drop_buffered_data
      end

      # Helpers for DataContainerTests

      def create_container
        @event_aggregator
      end

      def populate_container(sampler, n)
        n.times do |i|
          generate_event("whatever#{i}")
        end
      end

      include NewRelic::DataContainerTests

      # Helpers for CommonAggregatorTests

      def generate_event(name='operation_name', options = {})
        guid = fake_guid(16)

        event = [
          {
          'name' => name,
          'priority' => options[:priority] || rand,
          'sampled' => false,
          'guid'    => guid,
          'traceId' => guid,
          'timestamp' => (Time.now.to_f * 1000).round,
          'duration' => rand,
          'category' => 'custom'
          },
          {},
          {}
        ]

        @event_aggregator.record event: event
      end

      def last_events
        aggregator.harvest![1]
      end

      def aggregator
        @event_aggregator
      end

      def name_for(event)
        event[0]["name"]
      end

      def enabled_key
        :'span_events.enabled'
      end

      include NewRelic::CommonAggregatorTests

      def test_supportability_metrics_for_span_events
        with_config aggregator.class.capacity_key => 5 do
          12.times { generate_event }
        end

        assert_equal 5, last_events.size

        assert_metrics_recorded({'Supportability/SpanEvent/TotalEventsSeen' => { call_count: 12 }})
        assert_metrics_recorded({'Supportability/SpanEvent/TotalEventsSent' => { call_count:  5 }})
        assert_metrics_recorded({'Supportability/SpanEvent/Discarded'       => { call_count:  7 }})
      end
    end
  end
end
