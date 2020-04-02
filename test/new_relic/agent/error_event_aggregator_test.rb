# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require File.expand_path(File.join(File.dirname(__FILE__),'..','data_container_tests'))
require File.expand_path(File.join(File.dirname(__FILE__),'..','common_aggregator_tests'))
require 'new_relic/agent/error_event_aggregator'
require 'new_relic/agent/guid_generator'

module NewRelic
  module Agent
    class ErrorEventAggregatorTest < Minitest::Test
      def setup
        nr_freeze_time
        NewRelic::Agent::Harvester.any_instance.stubs(:harvest_thread_enabled?).returns(false)

        events = NewRelic::Agent.instance.events
        @span_id = NewRelic::Agent::GuidGenerator.generate_guid
        @error_event_aggregator = ErrorEventAggregator.new events
      end

      def teardown
        aggregator.reset!
        reset_error_event_buffer_state
      end

      # Helpers for DataContainerTests

      def create_container
        @error_event_aggregator
      end

      def populate_container(sampler, n)
        n.times do
          error = NewRelic::NoticedError.new "Controller/blogs/index", RuntimeError.new("Big Controller")
          payload = in_transaction{}.payload

          @error_event_aggregator.record error, payload, @span_id
        end
      end

      include NewRelic::DataContainerTests

      # Helpers for CommonAggregatorTests

      def generate_event(name = 'Controller/blogs/index', options = {})
        generate_error(name, options)
      end

      def last_events
        last_error_events
      end

      def aggregator
        @error_event_aggregator
      end

      def name_for(event)
        event[0]["transactionName"]
      end

      include NewRelic::CommonAggregatorTests

      # Tests specific to ErrorEventAggregator

      def test_generates_event_without_payload
        aggregator.record create_noticed_error('blogs/index'), nil, @span_id

        intrinsics, *_ = last_error_event

        assert_equal 'TransactionError', intrinsics['type']
        assert_in_delta Time.now.to_f, intrinsics['timestamp'], 0.001
        assert_equal "RuntimeError", intrinsics['error.class']
        assert_equal "Big Controller!", intrinsics['error.message']
      end

      def test_generates_event_from_error
        generate_error

        intrinsics, *_ = last_error_event

        assert_equal 'TransactionError', intrinsics['type']
        assert_in_delta Time.now.to_f, intrinsics['timestamp'], 0.001
        assert_equal "RuntimeError", intrinsics['error.class']
        assert_equal "Big Controller!", intrinsics['error.message']
        assert_equal "Controller/blogs/index", intrinsics['transactionName']
        assert_equal 0.1, intrinsics['duration']
        assert_equal 80, intrinsics['port']
      end

      def test_errors_not_noticed_when_disabled
        with_server_source :'error_collector.capture_events' => false do
          generate_error
          errors = last_error_events
          assert_empty errors
        end
      end

      def test_errors_not_noticed_when_error_collector_disabled
        config = {
          :'error_collector.enabled' => false,
          :'error_collector.capture_events' => true
        }
        with_server_source config do
          generate_error
          errors = last_error_events
          assert_empty errors
        end
      end

      class ImpossibleError < NoticedError
        def initialize
          super 'nowhere.rb', RuntimeError.new('Impossible')
        end
      end

      def test_aggregator_defers_error_event_creation
        with_config aggregator.class.capacity_key => 5 do
          5.times { generate_event }
          aggregator.expects(:create_event).never
          aggregator.record(ImpossibleError.new, { priority: -999.0 }, @span_id)
        end
      end

      #
      # Helpers
      #

      def last_error_events
        aggregator.harvest![1]
      end

      def last_error_event
        last_error_events.first
      end

      def reset_error_event_buffer_state
        # this is not ideal, but we need to reset these counts to clear out state
        # between tests
        buffer = aggregator.instance_variable_get :@buffer
        buffer.instance_variable_set :@seen_lifetime, 0
        buffer.instance_variable_set :@captured_lifetime, 0
      end

      def create_noticed_error txn_name, options = {}
        exception = options.delete(:exception) || RuntimeError.new("Big Controller!")
        noticed_error = NewRelic::NoticedError.new(txn_name, exception)
        noticed_error.request_uri = "http://site.com/blogs"
        noticed_error.request_port = 80
        noticed_error.attributes  = options.delete(:attributes)
        noticed_error.attributes_from_notice_error = options.delete(:custom_params) || {}
        noticed_error.attributes_from_notice_error.merge!(options)

        noticed_error
      end

      def create_transaction_payload name, options = {}
        {
          :name => name,
          :type => :controller,
          :start_timestamp => Time.now.to_f,
          :duration => 0.1,
          :priority => options[:priority] || rand
        }.update(options)
      end

      def generate_error name = 'Controller/blogs/index', options = {}
        error_options = options[:error_options] || {}
        error = create_noticed_error name, error_options

        payload_options = options[:payload_options] || {}
        payload_options[:priority] = options[:priority] if options[:priority]
        payload = create_transaction_payload name, payload_options

        @error_event_aggregator.record error, payload, @span_id
      end
    end
  end
end
