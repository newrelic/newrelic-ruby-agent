# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../test_helper', __FILE__)
require 'json'

module NewRelic
  module Agent
    class DistributedTracingCrossAgentTest < Minitest::Test
      def teardown
        NewRelic::Agent.drop_buffered_data
      end

      load_cross_agent_test("distributed_tracing/distributed_tracing").each do |test_case|

        test_case = symbolize_keys_in_object test_case
        test_case[:test_name] = test_case[:test_name].tr(" ", "_")
        define_method("test_#{test_case[:test_name]}") do
          config = {
            account_id:                    test_case[:account_id],
            trusted_account_key:           test_case[:trusted_account_key],
            'span_events.enabled':         test_case[:span_events_enabled],
            'distributed_tracing.enabled': true
          }

          with_config(config) do
            txn = run_transaction(test_case)
          end

          verify_metrics(test_case)
        end
      end

      def run_transaction(test_case)
        inbound_payloads = payloads_for(test_case)
        outbound_payloads = []

        in_transaction(in_transaction_options(test_case)) do |txn|
          inbound_payloads.each do |payload|
            txn.accept_distributed_trace_payload payload
            if txn.distributed_trace?
              txn.distributed_trace_payload.caller_transport_type = test_case[:transport_type]
            end

            if test_case[:raises_exception]
              e = StandardError.new 'ouchies'
              ::NewRelic::Agent.notice_error(e)
            end

            if test_case[:outbound_payloads]
              payloads = Array(test_case[:outbound_payloads])
              payloads.count.times do
                outbound_payloads << txn.create_distributed_trace_payload
              end
            end
          end
        end
      end

      def in_transaction_options(test_case)
        if test_case[:web_transaction]
          {
            transaction_name: "Controller/DistributedTracing/#{test_case[:test_name]}",
            category:         :controller,
            request:          stub(:path => '/')
          }
        else
          {
            transaction_name: "OtherTransaction/Background/#{test_case[:test_name]}",
            category:         :task
          }
        end
      end

      def payloads_for(test_case)
        if test_case.has_key?(:inbound_payloads)
          (test_case[:inbound_payloads] || [nil]).map(&:to_json)
        else
          []
        end
      end

      def verify_metrics(test_case)
        expected_metrics = test_case[:expected_metrics].inject({}) do |memo, (metric_name, call_count)|
          memo[metric_name] = {call_count: call_count}
          memo
        end

        assert_metrics_recorded expected_metrics
      end
    end
  end
end
