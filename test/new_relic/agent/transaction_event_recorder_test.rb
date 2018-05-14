# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/transaction_event_recorder'

module NewRelic
  module Agent
    class TransactionEventRecorderTest < Minitest::Test

      def setup
        @recorder = TransactionEventRecorder.new
        @attributes = nil
      end

      def test_synthetics_events_overflow_to_transaction_buffer
        with_config :'synthetics.events_limit' => 10 do
          20.times do |i|
            generate_request("syn_#{i}", :synthetics_resource_id => 100, :priority => 1.0 - i / 20.0)
          end

          _, txn_events = harvest_transaction_events!
          _, syn_events = harvest_synthetics_events!

          assert_equal 10, txn_events.size
          assert_equal 10, syn_events.size
        end
      end

      def test_synthetics_events_priority_bumps_go_to_main_buffer
        with_config :'synthetics.events_limit' => 10 do
          10.times do |i|
            generate_request("syn_#{i}", :timestamp => i + 10, :synthetics_resource_id => 100, :priority => 1.1,)
          end

          generate_request("syn_10", :timestamp => 1, :synthetics_resource_id => 100, :priority => 0.1,)

          _, txn_events = harvest_transaction_events!
          _, syn_events = harvest_synthetics_events!

          assert_equal 10, syn_events.size
          assert_equal 1.1, syn_events[0][0]["priority"]
          assert_equal 1, txn_events.size
        end
      end

      def test_normal_events_discarded_in_favor_sampled_events
        with_config :'analytics_events.max_samples_stored' => 5 do
          5.times { generate_request}
          5.times { |i| generate_request "sampled_#{i}", :priority => rand + 1 }

          _, events = harvest_transaction_events!

          expected = (0..4).map { |i| "Controller/sampled_#{i}" }

          assert_equal_unordered expected, events.map { |e| e[0]["name"] }
        end
      end

      def test_sampled_events_not_discarded_in_favor_of_normal_events
         with_config :'analytics_events.max_samples_stored' => 5 do
          5.times { |i| generate_request "sampled_#{i}", :priority => rand + 1 }
          5.times { generate_request}

          _, events = harvest_transaction_events!

          expected = (0..4).map { |i| "Controller/sampled_#{i}" }

          assert_equal_unordered expected, events.map { |e| e[0]["name"] }
        end
      end

      def generate_request name='whatever', options={}
        payload = {
          :name => "Controller/#{name}",
          :type => :controller,
          :start_timestamp => options[:timestamp] || Time.now.to_f,
          :duration => 0.1,
          :attributes => attributes,
          :error => false,
          :priority => options[:priority] || rand
        }.merge(options)

        @recorder.record payload
      end

      def attributes
        if @attributes.nil?
          filter = NewRelic::Agent::AttributeFilter.new(NewRelic::Agent.config)
          @attributes = NewRelic::Agent::Transaction::Attributes.new(filter)
        end

        @attributes
      end

      def harvest_transaction_events!
        @recorder.transaction_event_aggregator.harvest!
      end

      def harvest_synthetics_events!
        @recorder.synthetics_event_aggregator.harvest!
      end
    end
  end
end
