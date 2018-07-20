# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../test_helper', __FILE__)
require 'json'

module NewRelic
  module Agent
    class DistributedTracingCrossAgentTest < Minitest::Test
      def setup
        NewRelic::Agent.instance.adaptive_sampler.stubs(:sampled?).returns(true)
      end

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

        verify_transaction_intrinsics(test_case)
        verify_error_intrinsics(test_case)
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

      def merge_intrinsics(all_intrinsics)
        merged = {}

        all_intrinsics.each do |intrinsics|
          exact = intrinsics[:exact] || {}
          merged[:exact] ||= {}
          merged[:exact].merge!(exact)

          expected = intrinsics[:expected] || []
          merged[:expected] ||= []
          (merged[:expected] += expected).uniq!

          unexpected = intrinsics[:unexpected] || []
          merged[:unexpected] ||= []
          (merged[:unexpected] += unexpected).uniq!
        end

        merged
      end

      ALLOWED_EVENT_TYPES = Set.new %w(
        Transaction
        TransactionError
        Span
      )

      def intrinsics_for_event(test_case, event_type)
        unless ALLOWED_EVENT_TYPES.include? event_type
          raise %Q|Test fixture refers to unexpected event type "#{event_type}"|
        end

        return {} unless (intrinsics = test_case[:intrinsics])
        target_events = intrinsics[:target_events] || []
        return {} unless target_events.include? event_type

        common_intrinsics = intrinsics[:common] || {}
        transaction_intrinsics = intrinsics[event_type.to_sym] || {}

        merge_intrinsics [common_intrinsics, transaction_intrinsics]
      end

      def verify_intrinsics(test_case_intrinsics, actual_intrinsics, event_type)
        test_case_intrinsics[:exact].each do |k, v|
          assert_equal v,
                       actual_intrinsics[k.to_s],
                       %Q|Wrong "#{k}" #{event_type} intrinsic; expected #{v.inspect}, was #{actual_intrinsics[k.to_s].inspect}|
        end

        test_case_intrinsics[:expected].each do |attr|
          assert actual_intrinsics.has_key?(attr),
                 %Q|Missing expected #{event_type} intrinsic "#{attr}"|
        end

        test_case_intrinsics[:unexpected].each do |attr|
          refute actual_intrinsics.has_key?(attr),
                 %Q|Unexpected #{event_type} intrinsic "#{attr}"|
        end
      end

      def verify_transaction_intrinsics(test_case)
        test_case_intrinsics  = intrinsics_for_event(test_case, 'Transaction')
        actual_intrinsics, *_ = last_transaction_event
        verify_intrinsics(test_case_intrinsics, actual_intrinsics, 'Transaction')
      end

      def verify_error_intrinsics(test_case)
        return unless test_case[:raises_exception]

        test_case_intrinsics = intrinsics_for_event(test_case, 'TransactionError')
        actual_intrinsics, *_ = last_error_event
        verify_intrinsics(test_case_intrinsics, actual_intrinsics, 'TransactionError')
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
