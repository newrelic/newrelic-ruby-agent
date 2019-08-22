# -*- ruby -*-
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require File.expand_path(File.join(File.dirname(__FILE__),'..','data_container_tests'))
require File.expand_path(File.join(File.dirname(__FILE__),'..','common_aggregator_tests'))
require 'new_relic/agent/transaction_event_aggregator'
require 'new_relic/agent/transaction/attributes'
require 'new_relic/agent/transaction_event_primitive'

module NewRelic
  module Agent
    class TransactionEventAggregatorTest < Minitest::Test

      def setup
        nr_freeze_time
        events = NewRelic::Agent.instance.events
        @event_aggregator = TransactionEventAggregator.new events

        @attributes = nil
      end

      # Helpers for DataContainerTests

      def create_container
        @event_aggregator
      end

      def populate_container(sampler, n)
        n.times do |i|
          generate_request("whatever#{i}")
        end
      end

      include NewRelic::DataContainerTests

      # Helpers for CommonAggregatorTests

      def generate_event(name = 'Controller/whatever', options = {})
        generate_request(name, options)
      end

      def last_events
        last_transaction_events
      end

      def aggregator
        @event_aggregator
      end

      def name_for(event)
        event[0]["name"]
      end

      include NewRelic::CommonAggregatorTests

      # Tests specific to TransactionEventAggregator

      def test_record_accepts_a_block
        payload = generate_payload
        @event_aggregator.record(priority: 0.5) { TransactionEventPrimitive.create(payload) }
        assert_equal 1, last_transaction_events.size
      end

      def test_block_is_not_executed_unless_buffer_admits_event
        event = nil

        with_config :'analytics_events.max_samples_stored' => 5 do
          5.times { generate_request }

          payload = generate_payload
          @event_aggregator.record(priority: -1.0) do
            event = TransactionEventPrimitive.create(payload)
          end
        end

        assert_nil event, "Did not expect block to be executed"
        refute_includes last_transaction_events, event
      end

      #
      # Helpers
      #

      def generate_request(name='Controller/whatever', options={})
        payload = generate_payload name, options
        @event_aggregator.record event: TransactionEventPrimitive.create(payload)
      end

      def generate_payload(name='Controller/whatever', options={})
        {
          :name => name,
          :type => :controller,
          :start_timestamp => options[:timestamp] || Time.now.to_f,
          :duration => 0.1,
          :attributes => attributes,
          :error => false,
          :priority => options[:priority] || rand
        }.merge(options)
      end

      def attributes
        if @attributes.nil?
          filter = NewRelic::Agent::AttributeFilter.new(NewRelic::Agent.config)
          @attributes = NewRelic::Agent::Transaction::Attributes.new(filter)
        end

        @attributes
      end

      def last_transaction_events
        @event_aggregator.harvest![1]
      end

      def last_transaction_event
        events = last_transaction_events
        assert_equal 1, events.size
        events.first
      end
    end
  end
end
