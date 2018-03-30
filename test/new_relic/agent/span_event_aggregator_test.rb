# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require File.expand_path(File.join(File.dirname(__FILE__),'..','data_container_tests'))
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

      def generate_event(name, options = {})
        guid = generate_guid

        event = {
          'name' => name,
          'priority' => rand,
          'sampled' => false,
          'guid'    => guid,
          'traceId' => guid,
          'timestamp' => (Time.now.to_f * 1000).round,
          'duration' => rand,
          'category' => 'custom'
        }

        @event_aggregator.append event: event.merge(options)
      end

      def generate_guid
        SecureRandom.hex(16)
      end
    end
  end
end
