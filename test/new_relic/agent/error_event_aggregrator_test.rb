# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require File.expand_path(File.join(File.dirname(__FILE__),'..','data_container_tests'))
require 'new_relic/agent/error_event_aggregator'

module NewRelic
  module Agent
    class ErrorEventAggregatorTest < Minitest::Test
      def setup
        @error_event_aggregator = NewRelic::Agent::ErrorEventAggregator.new
      end

      def create_container
        @error_event_aggregator
      end

      def populate_container(sampler, n)
        n.times do |i|
          @error_event_aggregator.append_event i, i
        end
      end

      include NewRelic::DataContainerTests
    end
  end
end
