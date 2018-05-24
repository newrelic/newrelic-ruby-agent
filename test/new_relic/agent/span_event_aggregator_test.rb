# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../test_helper', __FILE__)
require File.expand_path('../../data_container_tests', __FILE__)
require File.expand_path('../../common_aggregator_tests', __FILE__)
require 'new_relic/agent/span_event_aggregator'
require 'securerandom'

module NewRelic
  module Agent
    class SpanEventAggregatorTest < Minitest::Test

      def setup
        nr_freeze_time
        @event_aggregator = SpanEventAggregator.new
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
        guid = SecureRandom.hex(16)

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

      include NewRelic::CommonAggregatorTests

      def test_max_samples_config_cannot_exceed_limit
        # the reservoir should not allow the capacity to be > 1000 regardless
        # of configuration

        with_config :'span_events.max_samples_stored' => 5000 do
          buffer = aggregator.instance_variable_get :@buffer
          assert_equal 1000, buffer.capacity
        end
      end

      # this overrides the common aggregator test since we have a lower max
      # capacity for the span event aggregator
      def test_does_not_drop_samples_when_used_from_multiple_threads
        with_config( aggregator.class.capacity_key => 1000 ) do
          threads = []
          9.times do
            threads << Thread.new do
              100.times { generate_event }
            end
          end
          threads.each { |t| t.join }

          assert_equal(9 * 100, last_events.size)
        end
      end
    end
  end
end
