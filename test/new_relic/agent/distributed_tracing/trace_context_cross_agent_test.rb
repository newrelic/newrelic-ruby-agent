# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path '../../../../test_helper', __FILE__

require 'json'

module NewRelic
  module Agent
    module DistributedTracing
      class TraceContextCrossAgentTest < Minitest::Test
        def setup
          NewRelic::Agent::Harvester.any_instance.stubs(:harvest_thread_enabled?).returns(false)
          NewRelic::Agent::Transaction::DistributedTracer.any_instance.stubs(:trace_context_active?).returns(true)
          @request_monitor = DistributedTracing::Monitor.new(EventListener.new)
          NewRelic::Agent.drop_buffered_data
        end

        def teardown
          NewRelic::Agent.drop_buffered_data
          NewRelic::Agent::Transaction::TraceContext::AccountHelpers.instance_variable_set :@trace_state_entry_key, nil
        end

        def verbose_attributes?
          !TraceContextCrossAgentTest.focus_tests.empty?
        end

        # This method, when returning a non-empty array, will cause the tests defined in the
        # JSON file to be skipped if they're not listed here.  Useful for focusing on specific
        # failing tests.
        def self.focus_tests
          ["trace_id_is_left_padded_and_priority_rounded"]
        end

        load_cross_agent_test("distributed_tracing/trace_context").each do |test_case|
          test_case['test_name'] = test_case['test_name'].tr(" ", "_")

          if focus_tests.empty? || focus_tests.include?(test_case['test_name'])

            define_method("test_#{test_case['test_name']}") do
              NewRelic::Agent.instance.adaptive_sampler.stubs(:sampled?).returns(test_case["force_sampled_true"])

              config = {
                :'distributed_tracing.enabled' => true,
                :'distributed_tracing.format'  => 'w3c',
                :account_id                    => test_case['account_id'],
                :primary_application_id        => "2827902",
                :trusted_account_key           => test_case['trusted_account_key'],
                :'span_events.enabled'         => test_case['span_events_enabled']
              }

              with_server_source(config) do
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
            accept_headers(test_case, txn)
            raise_exception(test_case)
            outbound_payloads = create_payloads(test_case, txn)
          end

          verify_metrics(test_case)
          verify_transaction_intrinsics(test_case)
          verify_error_intrinsics(test_case)
          verify_span_intrinsics(test_case)
          verify_outbound_payloads(test_case, outbound_payloads)
        end

        def accept_headers(test_case, txn)
          inbound_headers = headers_for(test_case)
          inbound_headers << nil if inbound_headers.empty?
          inbound_headers.each do |carrier|
            @request_monitor.on_before_call rack_format(test_case, carrier)
          end
        end

        def raise_exception(test_case)
          if test_case['raises_exception']
            e = StandardError.new 'ouchies'
            ::NewRelic::Agent.notice_error(e)
          end
        end

        def create_payloads(test_case, txn)
          outbound_payloads = []
          if test_case['outbound_payloads']
            payloads = Array(test_case['outbound_payloads'])
            [1, payloads.count].max.times do
              outbound_headers = {}
              # TODO: these two calls are too low-level.  We should
              # TODO: process at a higher-level to exercise intended
              # TODO: real-world scenarios of the agent.
              txn.distributed_tracer.append_payload outbound_headers
              txn.distributed_tracer.insert_headers outbound_headers
              outbound_payloads << outbound_headers
            end
          end
          outbound_payloads
        end

        def in_transaction_options(test_case)
          if test_case['web_transaction']
            {
              transaction_name: "Controller/DistributedTracing/#{test_case['test_name']}",
              category:         :controller,
              request:          stub(:path => '/')
            }
          else
            {
              transaction_name: "OtherTransaction/Background/#{test_case['test_name']}",
              category:         :task
            }
          end
        end

        def headers_for(test_case)
          Array(test_case['inbound_headers'])
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

        ALLOWED_EVENT_TYPES = %w{ Transaction TransactionError Span }

        def intrinsics_for_event(test_case, event_type)
          unless ALLOWED_EVENT_TYPES.include? event_type
            raise %Q|Test fixture refers to unexpected event type "#{event_type}"|
          end

          return {} unless (intrinsics = test_case['intrinsics'])
          target_events = intrinsics['target_events'] || []
          return {} unless target_events.include? event_type

          common_intrinsics = intrinsics['common'] || {}
          event_intrinsics  = intrinsics[event_type] || {}

          merge_intrinsics [common_intrinsics, event_intrinsics]
        end

        def verify_attributes(test_case_attributes, actual_attributes, event_type)
          if verbose_attributes?
            puts "", "*" * 80
            pp actual_attributes
            puts "*" * 80
          end

          (test_case_attributes['exact'] || []).each do |k, v|
            assert_equal v,
                         actual_attributes[k.to_s],
                         %Q|Wrong "#{k}" #{event_type} attribute; expected #{v.inspect}, was #{actual_attributes[k.to_s].inspect}|
          end

          (test_case_attributes['notequal'] || []).each do |k, v|
            refute_equal(
              v,
              actual_attributes[k.to_s],
              "#{event_type} #{k.to_s.inspect} attribute should not equal #{v.inspect}"
              )
          end

          (test_case_attributes['expected'] || []).each do |key|
            assert actual_attributes.has_key?(key),
                   %Q|Missing expected #{event_type} attribute "#{key}"|
          end

          (test_case_attributes['unexpected'] || []).each do |key|
            refute actual_attributes.has_key?(key),
                   %Q|Unexpected #{event_type} attribute "#{key}"|
          end
        end

        def verify_transaction_intrinsics(test_case)
          test_case_intrinsics = intrinsics_for_event(test_case, 'Transaction')
          return if test_case_intrinsics.empty?

          actual_intrinsics, *_ = last_transaction_event
          verify_attributes test_case_intrinsics, actual_intrinsics, 'Transaction'
        end

        def verify_error_intrinsics(test_case)
          return unless test_case['raises_exception']

          test_case_intrinsics = intrinsics_for_event(test_case, 'TransactionError')
          return if test_case_intrinsics.empty?

          actual_intrinsics, *_ = last_error_event
          verify_attributes test_case_intrinsics, actual_intrinsics, 'TransactionError'
        end

        def verify_span_intrinsics(test_case)
          return unless test_case['span_events_enabled']

          test_case_intrinsics = intrinsics_for_event(test_case, 'Span')
          return if test_case_intrinsics.empty?

          last_span_events = NewRelic::Agent.agent.span_event_aggregator.harvest![1]

          refute_empty last_span_events
          actual_intrinsics = last_span_events[0][0]

          verify_attributes test_case_intrinsics, actual_intrinsics, 'Span'
        end

        def verify_outbound_payloads(test_case, actual_payloads)
          return unless (test_case_payloads = test_case['outbound_payloads'])
          assert_equal test_case_payloads.count, actual_payloads.count

          test_case_payloads.zip(actual_payloads).each do |test_case_data, actual|
            context_hash = trace_context_headers_to_hash actual
            dotted_context_hash = NewRelic::Agent::Configuration::DottedHash.new context_hash
            stringified_hash = stringify_keys_in_object dotted_context_hash

            verify_attributes test_case_data, stringified_hash, 'Payload'
          end
        end

        def verify_metrics(test_case)
          expected_metrics = test_case['expected_metrics'].inject({}) do |memo, (metric_name, call_count)|
            memo[metric_name] = {call_count: call_count}
            memo
          end

          assert_metrics_recorded expected_metrics
        end

        def object_to_hash object
          object.instance_variables.inject({}) do |hash, variable_name|
            key = variable_name.to_s.sub(/^@/,'')
            hash[key] = object.instance_variable_get(variable_name)
            hash
          end
        end

        def trace_context_headers_to_hash carrier
          entry_key = NewRelic::Agent::Transaction::TraceContext::AccountHelpers.trace_state_entry_key
          header_data = TraceContext.parse \
              carrier: carrier,
              trace_state_entry_key: entry_key
          if header_data.trace_state_payload
            tracestate = object_to_hash header_data.trace_state_payload
            tracestate['tenant_id'] = entry_key.sub '@nr', ''
            tracestate['parent_type'] = header_data.trace_state_payload.parent_type_id
            tracestate['parent_application_id'] = header_data.trace_state_payload.parent_app_id
            tracestate['span_id'] = header_data.trace_state_payload.id
          else
            tracestate = nil
          end
          {
            'traceparent' => header_data.trace_parent,
            'tracestate' => tracestate
          }
        end

        # TODO: Fix this to deal with New Relic DT headers as well as W3C
        def rack_format test_case, carrier
          rack_headers = test_case.has_key?('transport_type') ? {'rack.url_scheme' => test_case['transport_type'].to_s.downcase} : {}
          carrier ||= {}
          rack_headers.merge({
            TraceContext::TRACE_PARENT_RACK => carrier[TraceContext::TRACE_PARENT],
            TraceContext::TRACE_STATE_RACK => carrier[TraceContext::TRACE_STATE]
          })
        end
      end
    end
  end
end
