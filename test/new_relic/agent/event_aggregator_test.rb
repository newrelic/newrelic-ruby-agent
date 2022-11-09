# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'
require_relative '../data_container_tests'
require 'new_relic/agent/event_aggregator'

module NewRelic
  module Agent
    class EventAggregatorTest < Minitest::Test
      class TestAggregator < EventAggregator
        named :TestAggregator
        capacity_key :cap_key
        enabled_key :enabled_key

        attr_reader :buffer

        def record(item)
          event = {'name' => "Event#{item}", 'priority' => rand}
          @buffer.append(event: [event])
          notify_if_full
        end
      end

      class FnTestAggregator < EventAggregator
        named :RubeGoldbergTestAggregator
        capacity_key :cap_key
        enabled_fn ->() { Agent.config[:enabled_key] && enabled_for_test }

        class << self
          attr_accessor :enabled_for_test
        end
      end

      class MultiKeyTestAggregator < EventAggregator
        named :RubeGoldbergTestAggregator
        capacity_key :cap_key
        enabled_keys :enabled_key, :enabled_key2
      end

      def setup
        NewRelic::Agent.config.add_config_for_testing(
          :cap_key => 100,
          :enabled_key => true,
          :enabled_key2 => true
        )

        @events = NewRelic::Agent.instance.events
        @aggregator = TestAggregator.new(@events)
      end

      def create_container
        @aggregator
      end

      def populate_container(container, n)
        n.times { |i| container.record(i) }
      end

      include NewRelic::DataContainerTests

      def test_it_has_a_name
        assert_equal 'TestAggregator', TestAggregator.named
      end

      def test_enabled_reflects_config_value
        assert_predicate @aggregator, :enabled?, "Expected enabled? to be true"

        with_server_source(:enabled_key => false) do
          refute @aggregator.enabled?, "Expected enabled? to be false"
        end
      end

      def test_enabled_uses_multiple_keys_by_default
        @aggregator = MultiKeyTestAggregator.new(@events)

        with_server_source(:enabled_key2 => true) do
          assert_predicate @aggregator, :enabled?
        end

        with_server_source(:enabled_key2 => false) do
          refute @aggregator.enabled?
        end
      end

      def test_after_harvest_invoked_with_report
        metadata = {:meta => true}
        @aggregator.buffer.stubs(:metadata).returns(metadata)
        @aggregator.expects(:after_harvest).with(metadata)
        @aggregator.harvest!
      end

      def test_notifies_full
        expects_logging(:debug, includes("TestAggregator capacity of 5 reached"))
        with_config(:cap_key => 5) do
          5.times { |i| @aggregator.record(i) }
        end
      end

      def test_notifies_full_only_once
        with_config(:cap_key => 5) do
          msg = "TestAggregator capacity of 5 reached"
          # this will trigger a message to be logged
          5.times { |i| @aggregator.record(i) }

          # we expect subsequent records not to trigger logging
          expects_logging(:debug, Not(includes(msg)))
          3.times { @aggregator.record('no logs') }
        end
      end

      def test_notifies_full_resets_after_harvest
        msg = "TestAggregator capacity of 5 reached"

        expects_logging(:debug, includes(msg))
        with_config(:cap_key => 5) do
          5.times { |i| @aggregator.record(i) }
        end

        @aggregator.harvest!

        expects_logging(:debug, includes(msg))
        with_config(:cap_key => 5) do
          5.times { |i| @aggregator.record(i) }
        end
      end

      def test_notifies_full_resets_after_buffer_reset
        msg = "TestAggregator capacity of 5 reached"

        expects_logging(:debug, includes(msg))
        with_config(:cap_key => 5) do
          5.times { |i| @aggregator.record(i) }
        end

        @aggregator.reset!

        expects_logging(:debug, includes(msg))
        with_config(:cap_key => 5) do
          5.times { |i| @aggregator.record(i) }
        end
      end

      def test_buffer_class_defaults_to_sampled_buffer
        assert_kind_of NewRelic::Agent::PrioritySampledBuffer, @aggregator.buffer
      end

      class TestBuffer < NewRelic::Agent::EventBuffer
      end

      def test_buffer_class_is_overridable
        klass = Class.new(EventAggregator) do
          named :TestAggregator2
          capacity_key :cap_key
          enabled_key :enabled_key
          buffer_class TestBuffer
          attr_reader :buffer
        end
        instance = klass.new(@events)

        assert_kind_of TestBuffer, instance.buffer
      end

      def test_buffer_adjusts_count_by_default_on_merge
        with_config(:cap_key => 5) do
          buffer = @aggregator.buffer

          4.times { |i| @aggregator.record(i) }
          last_harvest = @aggregator.harvest!

          assert_equal 4, buffer.seen_lifetime
          assert_equal 4, buffer.captured_lifetime
          assert_equal 4, last_harvest[0][:events_seen]

          4.times { |i| @aggregator.record(i) }
          @aggregator.merge!(last_harvest)

          reservoir_stats, samples = @aggregator.harvest!

          assert_equal 5, samples.size
          assert_equal 8, reservoir_stats[:events_seen]
          assert_equal 8, buffer.seen_lifetime
          assert_equal 5, buffer.captured_lifetime
        end
      end

      def test_buffer_adds_to_original_count_on_merge_when_specified
        with_config(:cap_key => 5) do
          buffer = @aggregator.buffer

          4.times { |i| @aggregator.record(i) }
          last_harvest = @aggregator.harvest!

          assert_equal 4, buffer.seen_lifetime
          assert_equal 4, buffer.captured_lifetime
          assert_equal 4, last_harvest[0][:events_seen]

          4.times { |i| @aggregator.record(i) }
          @aggregator.merge!(last_harvest, false)

          reservoir_stats, samples = @aggregator.harvest!

          assert_equal 5, samples.size
          assert_equal 8, reservoir_stats[:events_seen]
          assert_equal 12, buffer.seen_lifetime
          assert_equal 9, buffer.captured_lifetime
        end
      end
    end
  end
end
