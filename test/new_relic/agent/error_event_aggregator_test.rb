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
        freeze_time
        @error_event_aggregator = ErrorEventAggregator.new
      end

      def teardown
        error_event_aggregator.reset!
        reset_error_event_buffer_state
      end

      def create_container
        @error_event_aggregator
      end

      def populate_container(sampler, n)
        n.times do
          error = NewRelic::NoticedError.new "Controller/blogs/index", RuntimeError.new("Big Controller")
          payload = in_transaction{}.payload
          @error_event_aggregator.append_event error, payload
        end
      end

      include NewRelic::DataContainerTests

      def test_generates_event_without_payload
        error_event_aggregator.append_event create_noticed_error, nil

        intrinsics, *_ = last_error_event

        assert_equal "TransactionError", intrinsics[:type]
        assert_in_delta Time.now.to_f, intrinsics[:timestamp], 0.001
        assert_equal "RuntimeError", intrinsics[:'error.class']
        assert_equal "Big Controller!", intrinsics[:'error.message']
      end

      def test_generates_event_from_error
        generate_error

        intrinsics, *_ = last_error_event

        assert_equal "TransactionError", intrinsics[:type]
        assert_in_delta Time.now.to_f, intrinsics[:timestamp], 0.001
        assert_equal "RuntimeError", intrinsics[:'error.class']
        assert_equal "Big Controller!", intrinsics[:'error.message']
        assert_equal "Controller/blogs/index", intrinsics[:transactionName]
        assert_equal 0.1, intrinsics[:duration]
        assert_equal 80, intrinsics[:port]
      end

      def test_event_includes_synthetics
        generate_error :payload_options => {
          :synthetics_resource_id=>3,
          :synthetics_job_id=>4,
          :synthetics_monitor_id=>5
        }

        intrinsics, *_ = last_error_event

        assert_equal 3, intrinsics[:'nr.syntheticsResourceId']
        assert_equal 4, intrinsics[:'nr.syntheticsJobId']
        assert_equal 5, intrinsics[:'nr.syntheticsMonitorId']
      end

      def test_includes_mapped_metrics
        metrics = NewRelic::Agent::TransactionMetrics.new
        metrics.record_unscoped 'Datastore/all', 10
        metrics.record_unscoped 'GC/Transaction/all', 11
        metrics.record_unscoped 'WebFrontend/QueueTime', 12
        metrics.record_unscoped 'External/allWeb', 13

        generate_error :payload_options => {:metrics => metrics}

        intrinsics, *_ = last_error_event

        assert_equal 10.0, intrinsics["databaseDuration"]
        assert_equal 1, intrinsics["databaseCallCount"]
        assert_equal 11.0, intrinsics["gcCumulative"]
        assert_equal 12.0, intrinsics["queueDuration"]
        assert_equal 13.0, intrinsics["externalDuration"]
        assert_equal 1, intrinsics["externalCallCount"]
      end

      def test_includes_cat_attributes
        generate_error :payload_options => {:guid => "GUID", :referring_transaction_guid=>"REFERRING_GUID"}

        intrinsics, *_ = last_error_event

        assert_equal "GUID", intrinsics[:"nr.transactionGuid"]
        assert_equal "REFERRING_GUID", intrinsics[:"nr.referringTransactionGuid"]
      end

      def test_includes_custom_attributes
        attrs = {"user" => "Wes Mantooth", "channel" => 9}

        attributes = Transaction::Attributes.new(NewRelic::Agent.instance.attribute_filter)
        attributes.merge_custom_attributes attrs

        generate_error :error_options => {:attributes => attributes}

        _, custom_attrs, _ = last_error_event

        assert_equal attrs, custom_attrs
      end

      def test_includes_agent_attributes
        attributes = Transaction::Attributes.new(NewRelic::Agent.instance.attribute_filter)
        attributes.add_agent_attribute :'request.headers.referer', "http://blog.site/home", AttributeFilter::DST_ERROR_COLLECTOR
        attributes.add_agent_attribute :httpResponseCode, "200", AttributeFilter::DST_ERROR_COLLECTOR

        generate_error :error_options => {:attributes => attributes}

        _, _, agent_attrs = last_error_event

        expected = {:"request.headers.referer" => "http://blog.site/home", :httpResponseCode => "200"}
        assert_equal expected, agent_attrs
      end

      def test_respects_max_samples_stored
        with_config :'error_collector.max_event_samples_stored' => 5 do
          10.times { generate_error }
        end

        assert_equal 5, last_error_events.size
      end

      def test_reservoir_stats_reset_after_harvest
        5.times { generate_error }

        reservoir_stats, samples = error_event_aggregator.harvest!
        assert_equal 5, reservoir_stats[:events_seen]

        reservoir_stats, samples = error_event_aggregator.harvest!
        assert_equal 0, reservoir_stats[:events_seen]
      end

      def test_merge_merges_samples_back_into_buffer
        5.times { generate_error }

        last_harvest = error_event_aggregator.harvest!

        5.times { generate_error }

        error_event_aggregator.merge!(last_harvest)
        events = last_error_events

        assert_equal(10, events.size)
      end

      def test_merge_abides_by_max_samples_limit
        with_config :'error_collector.max_event_samples_stored' => 5 do
          4.times { generate_error }
          last_harvest = error_event_aggregator.harvest!

          4.times { generate_error }
          error_event_aggregator.merge!(last_harvest)

          assert_equal(5, last_error_events.size)
        end
      end

      def test_sample_counts_are_correct_after_merge
        with_config :'error_collector.max_event_samples_stored' => 5 do
          buffer = error_event_aggregator.instance_variable_get :@error_event_buffer

          4.times { generate_error }
          last_harvest = error_event_aggregator.harvest!

          assert_equal 4, buffer.seen_lifetime
          assert_equal 4, buffer.captured_lifetime
          assert_equal 4, last_harvest[0][:events_seen]

          4.times { generate_error }
          error_event_aggregator.merge! last_harvest

          reservoir_stats, samples = error_event_aggregator.harvest!

          assert_equal 5, samples.size
          assert_equal 8, reservoir_stats[:events_seen]
          assert_equal 8, buffer.seen_lifetime
          assert_equal 5, buffer.captured_lifetime
        end
      end

      def test_limits_total_number_of_samples_to_max_samples_stored
        with_config :'error_collector.max_event_samples_stored' => 100 do
          150.times { generate_error }
          assert_equal 100, last_error_events.size
        end
      end

      def test_resets_limits_on_harvest
        with_config :'error_collector.max_event_samples_stored' => 100 do
          50.times { generate_error }
          events_before = last_error_events
          assert_equal 50, events_before.size

          150.times { generate_error }
          events_after = last_error_events
          assert_equal 100, events_after.size
        end
      end

      def test_does_not_drop_samples_when_used_from_multiple_threads
        with_config :'error_collector.max_event_samples_stored' => 100 * 100 do
          threads = []
          25.times do
            threads << Thread.new do
              100.times{ generate_error }
            end
          end
          threads.each { |t| t.join }

          assert_equal(25 * 100, last_error_events.size)
        end
      end

      def test_errors_not_noticed_when_disabled
        with_config :'error_collector.capture_events' => false do
          generate_error
          errors = last_error_events
          assert_empty errors
        end
      end

      def test_errors_noticed_when_error_traces_disabled
        config = {
          :'error_collector.enabled' => false,
          :'error_collector.capture_events' => true
        }
        with_config config do
          generate_error
          errors = last_error_events
          assert_equal 1, errors.size
        end
      end

      def error_event_aggregator
        @error_event_aggregator
      end

      def last_error_events
        error_event_aggregator.harvest![1]
      end

      def last_error_event
        last_error_events.first
      end

      def reset_error_event_buffer_state
        # this is not ideal, but we need to reset these counts to clear out state
        # between tests
        buffer = error_event_aggregator.instance_variable_get :@error_event_buffer
        buffer.instance_variable_set :@seen_lifetime, 0
        buffer.instance_variable_set :@captured_lifetime, 0
      end

      def create_noticed_error options = {}
        exception = options.delete(:exception) || RuntimeError.new("Big Controller!")
        txn_name = "Controller/blogs/index"
        noticed_error = NewRelic::NoticedError.new(txn_name, exception)
        noticed_error.request_uri = "http://site.com/blogs"
        noticed_error.request_port = 80
        noticed_error.attributes  = options.delete(:attributes)
        noticed_error.attributes_from_notice_error = options.delete(:custom_params) || {}
        noticed_error.attributes_from_notice_error.merge!(options)

        noticed_error
      end

      def create_transaction_payload options = {}
        {
          :name => "Controller/blogs/index",
          :type => :controller,
          :start_timestamp => Time.now.to_f,
          :duration => 0.1
        }.update(options)
      end

      def generate_error options = {}
        error = create_noticed_error options[:error_options] || {}
        payload = create_transaction_payload options[:payload_options] || {}
        @error_event_aggregator.append_event error, payload
      end

      def generate_errors num_errors
        txn_name = "Controller/blogs/index"

        in_transaction :transaction_name => txn_name do |t|
          num_errors.times {t.notice_error RuntimeError.new}
        end
      end
    end
  end
end
