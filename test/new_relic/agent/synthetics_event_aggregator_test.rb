# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require File.expand_path(File.join(File.dirname(__FILE__),'..','data_container_tests'))
require 'new_relic/agent/synthetics_event_aggregator'
require 'new_relic/agent/transaction_event_primitive'

module NewRelic
  module Agent
    class SyntheticsEventAggregatorTest < Minitest::Test
      def setup
        freeze_time
        @synthetics_event_aggregator = SyntheticsEventAggregator.new
      end

      def teardown
        @synthetics_event_aggregator.reset!
      end

      def create_container
        @synthetics_event_aggregator
      end

      def populate_container(sampler, n)
        n.times do |i|
          generate_request
        end
      end

      include NewRelic::DataContainerTests

      def test_synthetics_aggregation_limits
        with_config :'synthetics.events_limit' => 10 do
          20.times do
            generate_request
          end

          assert_equal 10, last_synthetics_events.size
        end
      end

      def test_synthetics_events_kept_by_timestamp
        with_config :'synthetics.events_limit' => 10 do
          11.times do |i|
            _, rejected = generate_request('whatever', :timestamp => i)
            if i < 10
              assert_nil rejected, "Expected event to be accepted"
            else
              refute_nil rejected, "Expected event to be rejected"
              assert_equal 10.0, rejected.first["timestamp"]
            end
          end
        end
      end

      def test_sythetics_events_rejected_when_buffer_is_full_of_newer_events
        with_config :'synthetics.events_limit' => 10 do
          11.times do |i|
            generate_request 'whatever', :timestamp => i + 10.0
          end

          generate_request 'whatever', :timestamp => 1
          samples = last_synthetics_events
          assert_equal 10, samples.size
          timestamps = samples.map do |(main, _)|
            main["timestamp"]
          end.sort

          assert_equal ([1] + (10..18).to_a), timestamps
        end
      end

      def test_does_not_drop_samples_when_used_from_multiple_threads
        with_config :'synthetics.events_limit' => 100 * 100 do
          threads = []
          25.times do
            threads << Thread.new do
              100.times{ generate_request }
            end
          end
          threads.each { |t| t.join }

          assert_equal(25 * 100, last_synthetics_events.size)
        end
      end

      def test_events_not_recorded_when_disabled
        with_config :'analytics_events.enabled' => false do
          generate_request
          errors = last_synthetics_events
          assert_empty errors
        end
      end

      def test_includes_custom_attributes
        attrs = {"user" => "Wes Mantooth", "channel" => 9}

        attributes.merge_custom_attributes attrs

        generate_request

        _, custom_attrs, _ = last_synthetics_event

        assert_equal attrs, custom_attrs
      end

      def test_does_not_record_supportability_metric_when_no_events_dropped
        with_config :'synthetics.events_limit' => 20 do
          20.times do
            generate_request
          end

          @synthetics_event_aggregator.harvest!

          metric = 'Supportability/TransactionEventAggregator/synthetics_events_dropped'
          assert_metrics_not_recorded(metric)
        end
      end

      def test_synthetics_event_dropped_records_supportability_metrics
        with_config :'synthetics.events_limit' => 10 do
          20.times do
            generate_request
          end

          @synthetics_event_aggregator.harvest!

          metric = 'Supportability/SyntheticsEventAggregator/synthetics_events_dropped'
          assert_metrics_recorded(metric => { :call_count => 10 })
        end
      end

      def test_includes_agent_attributes
        attributes.add_agent_attribute :'request.headers.referer', "http://blog.site/home", AttributeFilter::DST_TRANSACTION_EVENTS
        attributes.add_agent_attribute :httpResponseCode, "200", AttributeFilter::DST_TRANSACTION_EVENTS

        generate_request

        _, _, agent_attrs = last_synthetics_event

        expected = {:"request.headers.referer" => "http://blog.site/home", :httpResponseCode => "200"}
        assert_equal expected, agent_attrs
      end

      def last_synthetics_events
        @synthetics_event_aggregator.harvest![1]
      end

      def last_synthetics_event
        last_synthetics_events.first
      end

      def generate_request name='whatever', options={}
        payload = {
          :name => "Controller/blogs/index",
          :type => :controller,
          :start_timestamp => options[:timestamp] || Time.now.to_f,
          :duration => 0.1,
          :synthetics_resource_id => 100,
          :attributes => attributes,
          :error => false
        }.merge(options)

        @synthetics_event_aggregator.append_or_reject TransactionEventPrimitive.create(payload)
      end

      def attributes
        if @attributes.nil?
          filter = NewRelic::Agent::AttributeFilter.new(NewRelic::Agent.config)
          @attributes = NewRelic::Agent::Transaction::Attributes.new(filter)
        end

        @attributes
      end
    end
  end
end
