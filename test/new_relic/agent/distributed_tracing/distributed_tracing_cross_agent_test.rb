# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'
require 'json'

module NewRelic::Agent
  module DistributedTracing
    class DistributedTracingCrossAgentTest < Minitest::Test
      def setup
        NewRelic::Agent::DistributedTracePayload.stubs(:connected?).returns(true)
        NewRelic::Agent::Harvester.any_instance.stubs(:harvest_thread_enabled?).returns(false)
      end

      def teardown
        NewRelic::Agent.drop_buffered_data
      end

      # This method, when returning a non-empty array, will cause the tests defined in the
      # JSON file to be skipped if they're not listed here.  Useful for focusing on specific
      # failing tests.
      def self.focus_tests
        []
      end

      load_cross_agent_test("distributed_tracing/distributed_tracing").each do |test_case|
        test_case['test_name'] = test_case['test_name'].tr(" ", "_")

        if focus_tests.empty? || focus_tests.include?(test_case['test_name'])
          define_method("test_#{test_case['test_name']}") do
            NewRelic::Agent.instance.adaptive_sampler.stubs(:sampled?).returns(test_case["force_sampled_true"])

            config = {
              :account_id => test_case['account_id'],
              :primary_application_id => "2827902",
              :trusted_account_key => test_case['trusted_account_key'],
              :'span_events.enabled' => test_case['span_events_enabled'],
              :'distributed_tracing.enabled' => true
            }

            with_config(config) do
              NewRelic::Agent.config.notify_server_source_added
              run_test_case(test_case)
            end
          end
        else
          define_method("test_#{test_case['test_name']}") do
            skip("marked pending by exclusion from #only_tests")
          end
        end
      end

      private

      def run_test_case(test_case)
        outbound_payloads = []
        if test_case['test_name'] =~ /^pending|^skip/ || test_case["pending"] || test_case["skip"]
          skip("marked pending in trace_context.json")
        end
        in_transaction(in_transaction_options(test_case)) do |txn|
          accept_payloads(test_case, txn)
          raise_exception(test_case)
          outbound_payloads = create_payloads(test_case, txn)
        end

        verify_metrics(test_case)
        verify_transaction_intrinsics(test_case)
        verify_error_intrinsics(test_case)
        verify_span_intrinsics(test_case)
        verify_outbound_payloads(test_case, outbound_payloads)
      end

      def accept_payloads(test_case, txn)
        test_case.has_key?('transport_type') ? {'rack.url_scheme' => test_case['transport_type'].to_s.downcase} : {}

        inbound_payloads = payloads_for(test_case)
        inbound_payloads.each do |payload|
          carrier = {"HTTP_NEWRELIC" => payload}
          DistributedTracing.accept_distributed_trace_headers(carrier, test_case['transport_type'])
        end
      end

      def raise_exception(test_case)
        if test_case['raises_exception']
          e = StandardError.new('ouchies')
          ::NewRelic::Agent.notice_error(e)
        end
      end

      def create_payloads(test_case, txn)
        outbound_payloads = []
        if test_case['outbound_payloads']
          payloads = Array(test_case['outbound_payloads'])
          payloads.count.times do
            payload = txn.distributed_tracer.create_distributed_trace_payload
            outbound_payloads << payload if payload
          end
        end
        outbound_payloads
      end

      def in_transaction_options(test_case)
        if test_case['web_transaction']
          {
            transaction_name: "Controller/DistributedTracing/#{test_case['test_name']}",
            category: :controller,
            request: stub(:path => '/')
          }
        else
          {
            transaction_name: "OtherTransaction/Background/#{test_case['test_name']}",
            category: :task
          }
        end
      end

      def payloads_for(test_case)
        if test_case.has_key?('inbound_payloads')
          (test_case['inbound_payloads'] || [nil]).map(&:to_json)
        else
          []
        end
      end

      def merge_intrinsics(all_intrinsics)
        merged = {}

        all_intrinsics.each do |intrinsics|
          exact = intrinsics['exact'] || {}
          merged['exact'] ||= {}
          merged['exact'].merge!(exact)

          expected = intrinsics['expected'] || []
          merged['expected'] ||= []
          (merged['expected'] += expected).uniq!

          unexpected = intrinsics['unexpected'] || []
          merged['unexpected'] ||= []
          (merged['unexpected'] += unexpected).uniq!
        end

        merged
      end

      ALLOWED_EVENT_TYPES = %w[ Transaction TransactionError Span ]

      def intrinsics_for_event(test_case, event_type)
        unless ALLOWED_EVENT_TYPES.include?(event_type)
          raise %Q(Test fixture refers to unexpected event type "#{event_type}")
        end

        return {} unless (intrinsics = test_case['intrinsics'])
        target_events = intrinsics['target_events'] || []
        return {} unless target_events.include?(event_type)

        common_intrinsics = intrinsics['common'] || {}
        event_intrinsics = intrinsics[event_type.to_sym] || {}

        merge_intrinsics([common_intrinsics, event_intrinsics])
      end

      def verify_attributes(test_case_attributes, actual_attributes, event_type)
        (test_case_attributes['exact'] || []).each do |k, v|
          msg = %Q(Wrong "#{k}" #{event_type} attribute; expected #{v.inspect}, was #{actual_attributes[k.to_s].inspect})
          assert_equal v, actual_attributes[k.to_s], msg
        end

        (test_case_attributes['expected'] || []).each do |key|
          msg = %Q(Missing expected #{event_type} attribute "#{key}")
          assert actual_attributes.has_key?(key), msg # rubocop:disable Minitest/AssertWithExpectedArgument
        end

        (test_case_attributes['unexpected'] || []).each do |key|
          msg = %Q(Unexpected #{event_type} attribute "#{key}")
          refute actual_attributes.has_key?(key), msg
        end
      end

      def verify_transaction_intrinsics(test_case)
        test_case_intrinsics = intrinsics_for_event(test_case, 'Transaction')
        return if test_case_intrinsics.empty?

        actual_intrinsics, *_ = last_transaction_event
        verify_attributes(test_case_intrinsics, actual_intrinsics, 'Transaction')
      end

      def verify_error_intrinsics(test_case)
        return unless test_case['raises_exception']

        test_case_intrinsics = intrinsics_for_event(test_case, 'TransactionError')
        return if test_case_intrinsics.empty?

        actual_intrinsics, *_ = last_error_event
        verify_attributes(test_case_intrinsics, actual_intrinsics, 'TransactionError')
      end

      def verify_span_intrinsics(test_case)
        return unless test_case['span_events_enabled']

        test_case_intrinsics = intrinsics_for_event(test_case, 'Span')
        return if test_case_intrinsics.empty?

        last_span_events = NewRelic::Agent.agent.span_event_aggregator.harvest![1]
        actual_intrinsics = last_span_events[0][0]

        verify_attributes(test_case_intrinsics, actual_intrinsics, 'Span')
      end

      def verify_outbound_payloads(test_case, actual_payloads)
        return unless (test_case_payloads = test_case['outbound_payloads'])
        assert_equal test_case_payloads.count, actual_payloads.count

        test_case_payloads.zip(actual_payloads).each do |test_case_data, actual|
          actual = stringify_keys_in_object(
            NewRelic::Agent::Configuration::DottedHash.new(
              JSON.parse(actual.text)
            )
          )
          verify_attributes(test_case_data, actual, 'Payload')
        end
      end

      def verify_metrics(test_case)
        expected_metrics = test_case['expected_metrics'].inject({}) do |memo, (metric_name, call_count)|
          memo[metric_name] = {call_count: call_count}
          memo
        end

        assert_metrics_recorded expected_metrics
      end
    end
  end
end
