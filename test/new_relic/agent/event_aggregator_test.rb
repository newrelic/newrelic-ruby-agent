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

        attr_reader :buffer

        def append item
          @buffer.append item
          notify_if_full
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

      def test_after_harvest_invoked_with_report
        metadata = {:meta => true}
        @aggregator.buffer.stubs(:metadata).returns(metadata)
        @aggregator.expects(:after_harvest).with(metadata)
        @aggregator.harvest!
      end

      def test_notifies_full
        expects_logging :debug, includes("TestAggregator capacity of 5 reached")
        with_config :cap_key => 5 do
          5.times { |i| @aggregator.append i}
        end
      end

      def test_notifies_full_only_once
        with_config :cap_key => 5 do
          msg = "TestAggregator capacity of 5 reached"
          # this will trigger a message to be logged
          5.times { |i| @aggregator.append i}

          # we expect subsequent appends not to trigger logging
          expects_logging :debug, Not(includes(msg))
          3.times {@aggregator.append 'no logs'}
        end
      end

      def test_notifies_full_resets_after_harvest
        msg = "TestAggregator capacity of 5 reached"

        expects_logging :debug, includes(msg)
        with_config :cap_key => 5 do
          5.times { |i| @aggregator.append i}
        end

        @aggregator.harvest!

        expects_logging :debug, includes(msg)
        with_config :cap_key => 5 do
          5.times { |i| @aggregator.append i}
        end
      end

      def test_notifies_full_resets_after_buffer_reset
        msg = "TestAggregator capacity of 5 reached"

        expects_logging :debug, includes(msg)
        with_config :cap_key => 5 do
          5.times { |i| @aggregator.append i}
        end

        @aggregator.reset!

        expects_logging :debug, includes(msg)
        with_config :cap_key => 5 do
          5.times { |i| @aggregator.append i}
        end
      end

      def test_buffer_class_defaults_to_sampled_buffer
        assert_kind_of NewRelic::Agent::SampledBuffer, @aggregator.buffer
      end

      def test_buffer_class_is_overridable
        klass = Class.new(EventAggregator) do
          named :TestAggregator2
          capacity_key :cap_key
          enabled_key :enabled_key
          buffer_class NewRelic::Agent::SizedBuffer
          attr_reader :buffer
        end
        instance = klass.new

        assert_kind_of NewRelic::Agent::SizedBuffer, instance.buffer
      end

      def test_buffer_adjusts_count_by_default_on_merge
        with_config :cap_key => 5 do
          buffer = @aggregator.buffer

          4.times { |i| @aggregator.append i  }
          last_harvest = @aggregator.harvest!

          assert_equal 4, buffer.seen_lifetime
          assert_equal 4, buffer.captured_lifetime
          assert_equal 4, last_harvest[0][:events_seen]

          4.times { |i| @aggregator.append i }
          @aggregator.merge! last_harvest

          reservoir_stats, samples = @aggregator.harvest!

          assert_equal 5, samples.size
          assert_equal 8, reservoir_stats[:events_seen]
          assert_equal 8, buffer.seen_lifetime
          assert_equal 5, buffer.captured_lifetime
        end
      end

      def test_buffer_adds_to_original_count_on_merge_when_specified
        with_config :cap_key => 5 do
          buffer = @aggregator.buffer

          4.times { |i| @aggregator.append i  }
          last_harvest = @aggregator.harvest!

          assert_equal 4, buffer.seen_lifetime
          assert_equal 4, buffer.captured_lifetime
          assert_equal 4, last_harvest[0][:events_seen]

          4.times { |i| @aggregator.append i }
          @aggregator.merge! last_harvest, false

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
