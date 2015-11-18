# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require File.expand_path(File.join(File.dirname(__FILE__),'..','data_container_tests'))
require 'new_relic/agent/synthetics_event_aggregator'

module NewRelic
  module Agent
    class SyntheticsAggregatorTest < Minitest::Test
      def setup
        freeze_time
        @synthetics_event_aggregator = SyntheticsEventAggregator.new
      end

      def teardown
        @synthetics_event_aggregator.reset!
      end

      def create_container
        @synthetics_event_aggregator
      end

      def populate_container(sampler, n)
        n.times do |i|
          generate_request("whatever#{i}")
        end
      end

      include NewRelic::DataContainerTests

      def test_synthetics_aggregation_limits
        with_config :'synthetics.events_limit' => 10 do
          20.times do
            generate_request
          end

          assert_equal 10, last_synthetics_events.size
        end
      end

      def test_synthetics_events_kept_by_timestamp
        with_config :'synthetics.events_limit' => 10 do
          11.times do |i|
            _, rejected = generate_request('synthetic', :timestamp => i)
            if i < 10
              assert_nil rejected, "Expected event to be accepted"
            else
              refute_nil rejected, "Expected event to be rejected"
              assert_equal 10.0, rejected.first["timestamp"]
            end
          end
        end
      end

      def test_sythetics_events_rejected_when_buffer_is_full_of_newer_events
        with_config :'synthetics.events_limit' => 10 do
          11.times do |i|
            generate_request('synthetic', :timestamp => i + 10.0)
          end

          generate_request('synthetic', :timestamp => 1)
          samples = last_synthetics_events
          assert_equal 10, samples.size
          timestamps = samples.map do |(main, _)|
            main["timestamp"]
          end.sort

          assert_equal ([1] + (10..18).to_a), timestamps
        end
      end

      def last_synthetics_events
        @synthetics_event_aggregator.harvest!
      end

      def last_synthetics_event
        last_synthetics_events.first
      end

      def generate_request(name='synthetic', options={})
        payload = {
          :name => "Controller/#{name}",
          :type => :controller,
          :start_timestamp => options[:timestamp] || Time.now.to_f,
          :duration => 0.1,
          :synthetics_resource_id => 100,
          :attributes => attributes,
          :error => false
        }.merge(options)

        @synthetics_event_aggregator.record_or_reject TransactionEvent.new(payload)
      end

      def attributes
        if @attributes.nil?
          filter = NewRelic::Agent::AttributeFilter.new(NewRelic::Agent.config)
          @attributes = NewRelic::Agent::Transaction::Attributes.new(filter)
        end

        @attributes
      end
    end
  end
end
