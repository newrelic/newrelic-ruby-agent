# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/attribute_filter'
require 'new_relic/agent/transaction/attributes'
require 'new_relic/agent/transaction_error_primitive'

module NewRelic
  module Agent
    class TransactionErrorPrimitiveTest < Minitest::Test
      def setup
        freeze_time
      end


      def test_event_includes_expected_intrinsics
        intrinsics, *_ = create_event

        assert_equal 'TransactionError', intrinsics['type']
        assert_in_delta Time.now.to_f, intrinsics['timestamp'], 0.001
        assert_equal "RuntimeError", intrinsics['error.class']
        assert_equal "Big Controller!", intrinsics['error.message']
        assert_equal "Controller/blogs/index", intrinsics['transactionName']
        assert_equal 0.1, intrinsics['duration']
        assert_equal 80, intrinsics['port']
      end

      def test_event_includes_synthetics
        intrinsics, *_ = create_event :payload_options => {
          :synthetics_resource_id=>3,
          :synthetics_job_id=>4,
          :synthetics_monitor_id=>5
        }

        assert_equal 3, intrinsics['nr.syntheticsResourceId']
        assert_equal 4, intrinsics['nr.syntheticsJobId']
        assert_equal 5, intrinsics['nr.syntheticsMonitorId']
      end

      def test_includes_mapped_metrics
        metrics = NewRelic::Agent::TransactionMetrics.new
        metrics.record_unscoped 'Datastore/all', 10
        metrics.record_unscoped 'GC/Transaction/all', 11
        metrics.record_unscoped 'WebFrontend/QueueTime', 12
        metrics.record_unscoped 'External/allWeb', 13

        intrinsics, *_ = create_event :payload_options => {:metrics => metrics}

        assert_equal 10.0, intrinsics["databaseDuration"]
        assert_equal 1, intrinsics["databaseCallCount"]
        assert_equal 11.0, intrinsics["gcCumulative"]
        assert_equal 12.0, intrinsics["queueDuration"]
        assert_equal 13.0, intrinsics["externalDuration"]
        assert_equal 1, intrinsics["externalCallCount"]
      end

      def test_includes_cat_attributes
        intrinsics, *_ = create_event :payload_options => {:guid => "GUID", :referring_transaction_guid=>"REFERRING_GUID"}

        assert_equal "GUID", intrinsics["nr.transactionGuid"]
        assert_equal "REFERRING_GUID", intrinsics["nr.referringTransactionGuid"]
      end

      def test_includes_custom_attributes
        attrs = {"user" => "Wes Mantooth", "channel" => 9}

        attributes = Transaction::Attributes.new(NewRelic::Agent.instance.attribute_filter)
        attributes.merge_custom_attributes attrs

        _, custom_attrs, _ = create_event :error_options => {:attributes => attributes}

        assert_equal attrs, custom_attrs
      end

      def test_includes_agent_attributes
        attributes = Transaction::Attributes.new(NewRelic::Agent.instance.attribute_filter)
        attributes.add_agent_attribute :'request.headers.referer', "http://blog.site/home", AttributeFilter::DST_ERROR_COLLECTOR
        attributes.add_agent_attribute :httpResponseCode, "200", AttributeFilter::DST_ERROR_COLLECTOR

        _, _, agent_attrs = create_event :error_options => {:attributes => attributes}

        expected = {:"request.headers.referer" => "http://blog.site/home", :httpResponseCode => "200"}
        assert_equal expected, agent_attrs
      end

      def create_event options = {}
        payload = generate_payload options[:payload_options] || {}
        error = create_noticed_error options[:error_options] || {}
        TransactionErrorPrimitive.create error, payload
      end

      def generate_payload options = {}
        {
          :name => "Controller/blogs/index",
          :type => :controller,
          :start_timestamp => Time.now.to_f,
          :duration => 0.1
        }.update(options)
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
    end
  end
end
