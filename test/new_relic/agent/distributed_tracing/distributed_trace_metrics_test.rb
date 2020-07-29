# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require File.expand_path '../../../../test_helper', __FILE__

module NewRelic::Agent
  class DistributedTraceMetricsTest < Minitest::Test

    def setup
      nr_freeze_time
      @config = {
        :account_id => "190",
        :primary_application_id => "46954",
        :disable_harvest_thread => true,
        :"distributed_tracing.enabled" => true
      }
      NewRelic::Agent.config.add_config_for_testing(@config)
    end

    def teardown
      NewRelic::Agent.config.remove_config(@config)
      NewRelic::Agent.config.reset_to_defaults
      reset_buffers_and_caches
    end

    def in_controller_transaction &blk
      in_transaction "controller_txn", :category => :controller do |txn|
        advance_time 1.0
        yield txn        
      end
    end

    def valid_trace_context_headers
      {
        NewRelic::HTTP_TRACEPARENT_KEY => '00-a8e67265afe2773a3c611b94306ee5c2-0996096a36a1cd29-01',
        NewRelic::HTTP_TRACESTATE_KEY => '190@nr=0-1-212311-51424-0996096a36a1cd29----1482959525577'
      }
    end

    def test_transaction_type_suffix
      in_transaction "test_txn" do |txn|
        txn.distributed_tracer.create_trace_state_payload
        assert_equal "allOther", DistributedTraceMetrics.transaction_type_suffix
      end

      in_transaction "controller", :category => :controller do |txn|
        assert_equal "allWeb", DistributedTraceMetrics.transaction_type_suffix
      end
    end

    def test_prefix_for_metric
      in_transaction "test_txn", :category => :controller do |txn|
        payload = txn.distributed_tracer.create_trace_state_payload
        assert payload, "payload should not be nil"

        prefix = DistributedTraceMetrics.prefix_for_metric "Test", txn, payload
        assert_equal "Test/App/190/46954/Unknown", prefix
      end
    end

    def test_record_metrics_for_transaction
      in_transaction "test_txn", :category => :controller do |txn|
        advance_time 1.0
        payload = txn.distributed_tracer.create_trace_state_payload
        assert payload, "payload should not be nil"

        DistributedTraceMetrics.record_metrics_for_transaction txn
      end

      assert_metrics_recorded([
        "DurationByCaller/Unknown/Unknown/Unknown/Unknown/all",
        "DurationByCaller/Unknown/Unknown/Unknown/Unknown/allWeb",
      ])
    end

    def test_record_metrics_for_transaction_with_payload
      in_transaction "controller_txn", :category => :controller do |txn|
        advance_time 1.0
        DistributedTracing.accept_distributed_trace_headers valid_trace_context_headers, NewRelic::HTTP
        DistributedTraceMetrics.record_metrics_for_transaction txn
      end

      assert_metrics_recorded([
        "DurationByCaller/Browser/212311/51424/HTTP/all",
        "DurationByCaller/Browser/212311/51424/HTTP/allWeb",
        "TransportDuration/Browser/212311/51424/HTTP/all",
        "TransportDuration/Browser/212311/51424/HTTP/allWeb",
      ])
      refute_metrics_recorded([
        "ErrorsByCaller/Browser/212311/51424/HTTP/all",
        "ErrorsByCaller/Browser/212311/51424/HTTP/allWeb",
        "ErrorsByCaller/Browser/212311/51424/Unknown/all",
        "ErrorsByCaller/Browser/212311/51424/Unknown/allWeb",
      ])
    end

    def test_record_metrics_for_transaction_with_garbage_transport_type
      in_transaction "controller_txn", :category => :controller do |txn|
        advance_time 1.0
        DistributedTracing.accept_distributed_trace_headers valid_trace_context_headers, "garbage"
        DistributedTraceMetrics.record_metrics_for_transaction txn
      end

      assert_metrics_recorded([
        "DurationByCaller/Browser/212311/51424/Unknown/all",
        "DurationByCaller/Browser/212311/51424/Unknown/allWeb",
        "TransportDuration/Browser/212311/51424/Unknown/all",
        "TransportDuration/Browser/212311/51424/Unknown/allWeb",
      ])
      refute_metrics_recorded([
        "ErrorsByCaller/Browser/212311/51424/HTTP/all",
        "ErrorsByCaller/Browser/212311/51424/HTTP/allWeb",
        "ErrorsByCaller/Browser/212311/51424/Unknown/all",
        "ErrorsByCaller/Browser/212311/51424/Unknown/allWeb",
      ])
    end

    def test_record_metrics_for_transaction_with_exception_handling
      in_transaction "controller_txn", :category => :controller do |txn|
        begin
          advance_time 1.0
          DistributedTracing.accept_distributed_trace_headers valid_trace_context_headers, NewRelic::HTTP
          raise "oops"
        rescue Exception => e
          Transaction.notice_error(e)
          DistributedTraceMetrics.record_metrics_for_transaction txn
        end
      end

      assert_metrics_recorded([
        "DurationByCaller/Browser/212311/51424/HTTP/all",
        "DurationByCaller/Browser/212311/51424/HTTP/allWeb",
        "TransportDuration/Browser/212311/51424/HTTP/all",
        "TransportDuration/Browser/212311/51424/HTTP/allWeb",
        "ErrorsByCaller/Browser/212311/51424/HTTP/all",
        "ErrorsByCaller/Browser/212311/51424/HTTP/allWeb",
      ])
    end

  end
end
