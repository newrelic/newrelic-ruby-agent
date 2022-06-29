# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative '../../test_helper'
require_relative '../data_container_tests'
require_relative '../common_aggregator_tests'
require 'new_relic/agent/synthetics_event_aggregator'
require 'new_relic/agent/transaction_event_primitive'

module NewRelic
  module Agent
    class SyntheticsEventAggregatorTest < Minitest::Test
      def setup
        nr_freeze_process_time
        @attributes = nil
        events = NewRelic::Agent.instance.events
        @synthetics_event_aggregator = SyntheticsEventAggregator.new events
      end

      def teardown
        @synthetics_event_aggregator.reset!
      end

      def create_container
        @synthetics_event_aggregator
      end

      def populate_container(sampler, n)
        n.times do |i|
          generate_request
        end
      end

      include NewRelic::DataContainerTests

      # Helpers for CommonAggregatorTests

      def generate_event(name = 'Controller/blogs/index', options = {})
        generate_request(name, options)
      end

      def last_events
        last_synthetics_events
      end

      def aggregator
        @synthetics_event_aggregator
      end

      def name_for(event)
        event[0]["name"]
      end

      include NewRelic::CommonAggregatorTests

      def test_includes_custom_attributes
        attrs = {"user" => "Wes Mantooth", "channel" => 9}

        attributes.merge_custom_attributes attrs

        generate_request

        _, custom_attrs, _ = last_synthetics_event

        assert_equal attrs, custom_attrs
      end

      def test_does_not_record_supportability_metric_when_no_events_dropped
        with_config :'synthetics.events_limit' => 20 do
          20.times do
            generate_request
          end

          @synthetics_event_aggregator.harvest!

          metric = 'Supportability/TransactionEventAggregator/synthetics_events_dropped'
          assert_metrics_not_recorded(metric)
        end
      end

      def test_synthetics_event_dropped_records_supportability_metrics
        with_config :'synthetics.events_limit' => 10 do
          20.times do
            generate_request
          end

          @synthetics_event_aggregator.harvest!

          metric = 'Supportability/SyntheticsEventAggregator/synthetics_events_dropped'
          assert_metrics_recorded(metric => {:call_count => 10})
        end
      end

      def test_lower_priority_events_discarded_in_favor_higher_priority_events
        with_config aggregator.class.capacity_key => 5 do
          10.times { |i| generate_event "event_#{i}" }
          # Each event gets a timestamp, which is used to determine priority
          # (older events are higher priority)

          _, events = aggregator.harvest!

          expected = (0..4).map { |i| "event_#{i}" }

          assert_equal_unordered expected, events.map { |e| name_for(e) }
        end
      end

      def test_includes_agent_attributes
        attributes.add_agent_attribute :'request.headers.referer', "http://blog.site/home", AttributeFilter::DST_TRANSACTION_EVENTS
        attributes.add_agent_attribute :'http.statusCode', 200, AttributeFilter::DST_TRANSACTION_EVENTS

        generate_request

        _, _, agent_attrs = last_synthetics_event

        expected = {:"request.headers.referer" => "http://blog.site/home", :'http.statusCode' => 200}
        assert_equal expected, agent_attrs
      end

      def test_aggregator_defers_synthetics_event_creation
        with_config aggregator.class.capacity_key => 5 do
          5.times { generate_event }
          aggregator.expects(:create_event).never

          payload = {
            :name => "Doesnt/matter",
            :synthetics_resource_id => 100,
            :priority => 0.123
          }

          aggregator.record TransactionEventPrimitive.create(payload)
        end
      end

      def last_synthetics_events
        @synthetics_event_aggregator.harvest![1]
      end

      def last_synthetics_event
        last_synthetics_events.first
      end

      def generate_request name = 'Controller/whatever', options = {}
        payload = {
          :name => name,
          :type => :controller,
          :start_timestamp => options[:timestamp] || Process.clock_gettime(Process::CLOCK_REALTIME),
          :duration => 0.1,
          :synthetics_resource_id => 100,
          :attributes => attributes,
          :error => false,
          :priority => rand
        }.merge(options)

        @synthetics_event_aggregator.record TransactionEventPrimitive.create(payload)
      end

      def attributes
        if @attributes.nil?
          filter = NewRelic::Agent::AttributeFilter.new(NewRelic::Agent.config)
          @attributes = NewRelic::Agent::Attributes.new(filter)
        end

        @attributes
      end
    end
  end
end
