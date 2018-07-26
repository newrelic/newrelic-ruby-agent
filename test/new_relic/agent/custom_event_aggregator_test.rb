# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require File.expand_path(File.join(File.dirname(__FILE__),'..','data_container_tests'))
require File.expand_path(File.join(File.dirname(__FILE__),'..','common_aggregator_tests'))

require 'new_relic/agent/custom_event_aggregator'

module NewRelic::Agent
  class CustomEventAggregatorTest < Minitest::Test
    def setup
      nr_freeze_time
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

    # Helpers for CommonAggregatorTests

    def generate_event(name = 'Controller/blogs/index', options = {})
      generate_request(name, options)
    end

    def generate_request(name='Controller/whatever', options={})
      payload = options.merge(:name => name)

      @aggregator.record :custom, payload
    end

    def last_events
      aggregator.harvest![1]
    end

    def aggregator
      @aggregator
    end

    def name_for(event)
      event[1]["name"]
    end

    include NewRelic::CommonAggregatorTests

    def test_record_by_default_limit
      max_samples = NewRelic::Agent.config[:'custom_insights_events.max_samples_stored']
      n = max_samples + 1
      n.times do |i|
        @aggregator.record(:footype, :number => i)
      end

      metadata, results = @aggregator.harvest!
      assert_equal(max_samples, metadata[:reservoir_size])
      assert_equal(n, metadata[:events_seen])
      assert_equal(max_samples, results.size)
    end

    def test_lowering_limit_truncates_buffer
      orig_max_samples = NewRelic::Agent.config[:'custom_insights_events.max_samples_stored']

      orig_max_samples.times do |i|
        @aggregator.record(:footype, :number => i)
      end

      new_max_samples = orig_max_samples - 10
      with_config(:'custom_insights_events.max_samples_stored' => new_max_samples) do
        metadata, results = @aggregator.harvest!
        assert_equal(new_max_samples, metadata[:reservoir_size])
        assert_equal(orig_max_samples, metadata[:events_seen])
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

        _, events = @aggregator.harvest!

        assert_equal(10, events.size)
      end
    end

    def test_record_adds_type_and_timestamp
      t0 = Time.now
      @aggregator.record(:type_a, :foo => :bar, :baz => :qux)

      _, events = @aggregator.harvest!

      assert_equal(1, events.size)
      event = events.first

      event[0].delete('priority')

      assert_equal({ 'type' => 'type_a', 'timestamp' => t0.to_i }, event[0])
      assert_equal({ 'foo'  => 'bar'   , 'baz'       => 'qux'   }, event[1])
    end

    def test_records_supportability_metrics_after_harvest
      with_config :'custom_insights_events.max_samples_stored' => 5 do
        engine = NewRelic::Agent.instance.stats_engine
        engine.expects(:tl_record_supportability_metric_count).with("Events/Customer/Seen", 9)
        engine.expects(:tl_record_supportability_metric_count).with("Events/Customer/Sent", 5)
        engine.expects(:tl_record_supportability_metric_count).with("Events/Customer/Dropped", 4)

        9.times { @aggregator.record(:t, :foo => :bar) }
        @aggregator.harvest!
      end
    end

    def test_aggregator_defers_custom_event_creation
      with_config aggregator.class.capacity_key => 5 do
        5.times { generate_event }
        aggregator.expects(:create_event).never
        aggregator.record('ImpossibleEvent', { priority: -999.0 })
      end
    end
  end
end
