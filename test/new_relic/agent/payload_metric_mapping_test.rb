# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/transaction_metrics'
require 'new_relic/agent/payload_metric_mapping'

module NewRelic
  module Agent
    class PayloadMetricMappingTest < Minitest::Test
      def setup
        @metrics = TransactionMetrics.new
      end

      def test_maps_datastore_all
        @metrics.record_unscoped 'Datastore/all' do |stats|
         stats.total_call_time = 42
         stats.call_count = 3
        end

        result = {}
        PayloadMetricMapping.append_mapped_metrics @metrics, result

        assert_equal 42, result['databaseDuration']
        assert_equal 3, result['databaseCallCount']
      end

      def test_maps_gc_transaction_all
        @metrics.record_unscoped 'GC/Transaction/all', 42

        result = {}
        PayloadMetricMapping.append_mapped_metrics @metrics, result

        assert_equal 42, result['gcCumulative']
      end

      def test_maps_web_frontend_queue_time
        @metrics.record_unscoped 'WebFrontend/QueueTime', 42

        result = {}
        PayloadMetricMapping.append_mapped_metrics @metrics, result

        assert_equal 42, result['queueDuration']
      end

      def test_maps_external_all_web
        @metrics.record_unscoped 'External/allWeb' do |stats|
         stats.total_call_time = 42
         stats.call_count = 3
        end

        result = {}
        PayloadMetricMapping.append_mapped_metrics @metrics, result

        assert_equal 42, result['externalDuration']
        assert_equal 3, result['externalCallCount']
      end

      def test_maps_external_all_other
        @metrics.record_unscoped 'External/allOther' do |stats|
         stats.total_call_time = 42
         stats.call_count = 3
        end

        result = {}
        PayloadMetricMapping.append_mapped_metrics @metrics, result

        assert_equal 42, result['externalDuration']
        assert_equal 3, result['externalCallCount']
      end
    end
  end
end
