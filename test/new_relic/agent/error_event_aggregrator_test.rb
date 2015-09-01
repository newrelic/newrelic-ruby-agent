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
        freeze_time
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

      def test_generates_event_from_error
        txn_name = "Controller/blogs/index"

        txn = in_transaction :transaction_name => txn_name do |t|
          t.notice_error RuntimeError.new "Big Controller"
        end

        error = last_traced_error
        payload = txn.payload

        @error_event_aggregator.append_event error, payload
        errors = @error_event_aggregator.harvest!
        intrinsics, *_ = errors.first

        assert_equal "TransactionError", intrinsics[:type]
        assert_equal Time.now.to_f, intrinsics[:timestamp]
        assert_equal "RuntimeError", intrinsics[:'error.class']
        assert_equal "Big Controller", intrinsics[:'error.message']
        assert_equal txn_name, intrinsics[:transactionName]
        assert_equal payload[:duration], intrinsics[:duration]
      end

      def test_event_includes_synthetics
        txn_name = "Controller/blogs/index"

        txn = in_transaction :transaction_name => txn_name do |t|
          t.raw_synthetics_header = "fake"
          t.synthetics_payload = [1,2,3,4,5]
          t.notice_error RuntimeError.new "Big Controller"
        end

        error = last_traced_error
        payload = txn.payload

        @error_event_aggregator.append_event error, payload
        errors = @error_event_aggregator.harvest!
        intrinsics, *_ = errors.first

        assert_equal 3, intrinsics[:'nr.syntheticsResourceId']
        assert_equal 4, intrinsics[:'nr.syntheticsJobId']
        assert_equal 5, intrinsics[:'nr.syntheticsMonitorId']
      end

      def test_includes_mapped_metrics
        txn_name = "Controller/blogs/index"

        txn = in_transaction :transaction_name => txn_name do |t|
          NewRelic::Agent.record_metric 'Datastore/all', 10
          NewRelic::Agent.record_metric 'GC/Transaction/all', 11
          NewRelic::Agent.record_metric 'WebFrontend/QueueTime', 12
          NewRelic::Agent.record_metric 'External/allWeb', 13
          t.notice_error RuntimeError.new "Big Controller"
        end

        error = last_traced_error
        payload = txn.payload

        @error_event_aggregator.append_event error, payload
        errors = @error_event_aggregator.harvest!
        intrinsics, *_ = errors.first

        assert_equal 10.0, intrinsics["databaseDuration"]
        assert_equal 1, intrinsics["databaseCallCount"]
        assert_equal 11.0, intrinsics["gcCumulative"]
        assert_equal 12.0, intrinsics["queueDuration"]
        assert_equal 13.0, intrinsics["externalDuration"]
        assert_equal 1, intrinsics["externalCallCount"]
      end

      def test_includes_cat_attributes
        txn_name = "Controller/blogs/index"

        txn = in_transaction :transaction_name => txn_name do |t|
          state = TransactionState.tl_get
          state.is_cross_app_caller = true
          state.referring_transaction_info = ["REFERRING_GUID"]
          t.notice_error RuntimeError.new "Big Controller"
        end

        error = last_traced_error
        payload = txn.payload

        @error_event_aggregator.append_event error, payload
        errors = @error_event_aggregator.harvest!
        intrinsics, *_ = errors.first

        assert_equal txn.guid, intrinsics[:"nr.transactionGuid"]
        assert_equal "REFERRING_GUID", intrinsics[:"nr.referringTransactionGuid"]
      end
    end
  end
end
