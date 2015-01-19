# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require File.expand_path(File.join(File.dirname(__FILE__),'..','data_container_tests'))

require 'new_relic/agent/custom_event_aggregator'

module NewRelic::Agent
  class CustomEventAggregatorTest < Minitest::Test
    def setup
      freeze_time
      @aggregator = NewRelic::Agent::CustomEventAggregator.new
    end

    # Helpers for DataContainerTests

    def create_container
      @aggregator
    end

    def populate_container(container, n)
      n.times do |i|
        container.record(:atype, { :number => i })
      end
    end

    include NewRelic::DataContainerTests

    def test_record_by_default_limit
      max_samples = NewRelic::Agent.config[:'custom_insights_events.max_samples_stored']
      n = max_samples + 1
      n.times do |i|
        @aggregator.record(:footype, :number => i)
      end

      results = @aggregator.harvest!
      assert_equal(max_samples, results.size)
    end

    def test_lowering_limit_truncates_buffer
      orig_max_samples = NewRelic::Agent.config[:'custom_insights_events.max_samples_stored']

      orig_max_samples.times do |i|
        @aggregator.record(:footype, :number => i)
      end

      new_max_samples = orig_max_samples - 10
      with_config(:'custom_insights_events.max_samples_stored' => new_max_samples) do
        results = @aggregator.harvest!
        assert_equal(new_max_samples, results.size)
      end
    end

    def test_merge_respects_event_limits_by_type
      with_config(:'custom_insights_events.max_samples_stored' => 10) do
        11.times do |i|
          @aggregator.record(:t, :foo => :bar)
        end
        old_events = @aggregator.harvest!

        3.times do |i|
          @aggregator.record(:t, :foo => :bar)
        end

        @aggregator.merge!(old_events)

        events = @aggregator.harvest!

        assert_equal(10, events.size)
      end
    end

    def test_record_adds_type_and_timestamp
      t0 = Time.now
      @aggregator.record(:type_a, :foo => :bar, :baz => :qux)

      events = @aggregator.harvest!

      assert_equal(1, events.size)
      event = events.first

      assert_equal({ 'type' => 'type_a', 'timestamp' => t0.to_i }, event[0])
      assert_equal({ 'foo'  => 'bar'   , 'baz'       => 'qux'   }, event[1])
    end
  end
end
