# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require File.expand_path(File.join(File.dirname(__FILE__),'..','data_container_tests'))
require 'new_relic/agent/event_aggregator'

module NewRelic
  module Agent
    class EventAggregatorTest < Minitest::Test
      class TestAggregator < EventAggregator
        named :TestAggregator
        capacity_key :cap_key
        enabled_key :enabled_key

        def append item
          @buffer.append item
        end
      end

      def setup
        NewRelic::Agent.config.add_config_for_testing(
          :cap_key => 100,
          :enabled_key => true
        )

        @aggregator = TestAggregator.new
      end

      def create_container
        @aggregator
      end

      def populate_container(container, n)
        n.times { |i| container.append i }
      end

      include NewRelic::DataContainerTests

      def test_it_has_a_name
        assert_equal 'TestAggregator', TestAggregator.named
      end

      def test_enabled_relects_config_value
        assert @aggregator.enabled?, "Expected enabled? to be true"

        with_config :enabled_key => false do
          refute @aggregator.enabled?, "Expected enabled? to be false"
        end
      end
    end
  end
end
