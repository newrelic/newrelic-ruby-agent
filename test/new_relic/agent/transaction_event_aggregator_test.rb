# -*- ruby -*-
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require File.expand_path(File.join(File.dirname(__FILE__),'..','data_container_tests'))
require 'new_relic/agent/transaction_event_aggregator'
require 'new_relic/agent/transaction/attributes'
require 'new_relic/agent/transaction_event_primitive'

module NewRelic
  module Agent
    class TransactionEventAggregatorTest < Minitest::Test

      def setup
        freeze_time
        @event_aggregator = TransactionEventAggregator.new

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

      # Tests

      def test_samples_on_transaction_finished_event
        generate_request
        assert_equal 1, last_transaction_events.length
      end

      def test_records_background_tasks
        generate_request('a', :type => :controller)
        generate_request('b', :type => :background)
        assert_equal 2, last_transaction_events.size
      end

      def test_can_disable_sampling_for_analytics
        with_config( :'analytics_events.enabled' => false ) do
          generate_request
          assert last_transaction_events.empty?
        end
      end

      def test_harvest_returns_previous_sample_list
        5.times { generate_request }

        _, old_samples = @event_aggregator.harvest!

        assert_equal 5, old_samples.size
        assert_equal 0, last_transaction_events.size
      end

      def test_merge_merges_samples_back_into_buffer
        5.times { generate_request }
        old_samples = @event_aggregator.harvest!
        5.times { generate_request }

        @event_aggregator.merge!(old_samples)

        assert_equal(10, last_transaction_events.size)
      end

      def test_merge_abides_by_max_samples_limit
        with_config(:'analytics_events.max_samples_stored' => 5) do
          4.times { generate_request }
          old_samples = @event_aggregator.harvest!
          4.times { generate_request }

          @event_aggregator.merge!(old_samples)
          assert_equal(5, last_transaction_events.size)
        end
      end

      def test_sample_counts_are_correct_after_merge
        with_config :'analytics_events.max_samples_stored' => 5 do
          buffer = @event_aggregator.instance_variable_get :@buffer

          4.times { generate_request }
          last_harvest = @event_aggregator.harvest!

          assert_equal 4, buffer.seen_lifetime
          assert_equal 4, buffer.captured_lifetime
          assert_equal 4, last_harvest[0][:events_seen]

          4.times { generate_request }
          @event_aggregator.merge! last_harvest

          reservoir_stats, samples = @event_aggregator.harvest!

          assert_equal 5, samples.size
          assert_equal 8, reservoir_stats[:events_seen]
          assert_equal 8, buffer.seen_lifetime
          assert_equal 5, buffer.captured_lifetime
        end
      end

      def test_limits_total_number_of_samples_to_max_samples_stored
        with_config( :'analytics_events.max_samples_stored' => 100 ) do
          150.times { generate_request }
          assert_equal 100, last_transaction_events.size
        end
      end

      def test_resets_limits_on_harvest
        with_config( :'analytics_events.max_samples_stored' => 100 ) do
          50.times { generate_request('before') }
          samples_before = last_transaction_events
          assert_equal 50, samples_before.size

          150.times { generate_request('after') }
          samples_after = last_transaction_events
          assert_equal 100, samples_after.size

          assert_equal 0, (samples_before & samples_after).size
        end
      end

      def test_does_not_drop_samples_when_used_from_multiple_threads
        with_config( :'analytics_events.max_samples_stored' => 100 * 100 ) do
          threads = []
          25.times do
            threads << Thread.new do
              100.times { generate_request }
            end
          end
          threads.each { |t| t.join }

          assert_equal(25 * 100, last_transaction_events.size)
        end
      end

      def test_append_accepts_a_block
        payload = generate_payload
        @event_aggregator.append { TransactionEventPrimitive.create(payload) }
        assert_equal 1, last_transaction_events.size
      end

      def test_block_is_not_executed_unless_buffer_admits_event
        event = nil

        with_config :'analytics_events.max_samples_stored' => 5 do
          5.times { generate_request }

          #cause sample to be discarded by the sampled buffer
          buffer = @event_aggregator.instance_variable_get :@buffer
          buffer.stubs(:rand).returns(6)

          payload = generate_payload
          @event_aggregator.append do
            event = TransactionEventPrimitive.create(payload)
          end
        end

        assert_nil event, "Did not expect block to be executed"
        refute_includes last_transaction_events, event
      end

      #
      # Helpers
      #

      def generate_request(name='whatever', options={})
        payload = generate_payload name, options
        @event_aggregator.append TransactionEventPrimitive.create(payload)
      end

      def generate_payload(name='whatever', options={})
        {
          :name => "Controller/#{name}",
          :type => :controller,
          :start_timestamp => options[:timestamp] || Time.now.to_f,
          :duration => 0.1,
          :attributes => attributes,
          :error => false
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
