# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'
require 'json'

module NewRelic
  module Agent
    module DistributedTracing
      class TraceContextCrossAgentTest < Minitest::Test
        def setup
          NewRelic::Agent::DistributedTracePayload.stubs(:connected?).returns(true)
          NewRelic::Agent::Agent.any_instance.stubs(:connected?).returns(true)
          NewRelic::Agent::Harvester.any_instance.stubs(:harvest_thread_enabled?).returns(false)
          NewRelic::Agent::Transaction::DistributedTracer.any_instance.stubs(:trace_context_active?).returns(true)
          @request_monitor = DistributedTracing::Monitor.new(EventListener.new)
          reset_buffers_and_caches
        end

        def teardown
          NewRelic::Agent::DistributedTracePayload.unstub(:connected?)
          NewRelic::Agent::Agent.any_instance.unstub(:connected?)
          NewRelic::Agent::Harvester.any_instance.unstub(:harvest_thread_enabled?)
          NewRelic::Agent::Transaction::DistributedTracer.any_instance.unstub(:trace_context_active?)
          reset_buffers_and_caches
        end

        def verbose_attributes?
          !TraceContextCrossAgentTest.focus_tests.empty?
        end

        # This method, when returning a non-empty array, will cause the tests defined in the
        # JSON file to be skipped if they're not listed here.  Useful for focusing on specific
        # failing tests.
        def self.focus_tests
          []
        end

        load_cross_agent_test("distributed_tracing/trace_context").each do |test_case|
          test_case['test_name'] = test_case['test_name'].tr(" ", "_")

          if focus_tests.empty? || focus_tests.include?(test_case['test_name'])

            define_method("test_#{test_case['test_name']}") do
              NewRelic::Agent.instance.adaptive_sampler.stubs(:sampled?).returns(test_case["force_sampled_true"])

              config = {
                :'distributed_tracing.enabled' => true,
                :account_id => test_case['account_id'],
                :primary_application_id => "2827902",
                :'analytics_events.enabled' => test_case.fetch('transaction_events_enabled', true),
                :trusted_account_key => test_case['trusted_account_key'],
                :'span_events.enabled' => test_case.fetch('span_events_enabled', true)
              }

              with_server_source(config) do
                run_test_case(test_case)
              end
            end
          else
            define_method("test_#{test_case['test_name']}") do
              skip("marked pending by exclusion from #focus_tests")
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
            DistributedTracing.accept_distributed_trace_headers( \
              rack_format(test_case, carrier),
              test_case['transport_type']
            )
          end
        end

        def raise_exception(test_case)
          if test_case['raises_exception']
            e = StandardError.new('ouchies')
            ::NewRelic::Agent.notice_error(e)
          end
        end

        def create_newrelic_payloads(test_case, txn, w3c_payloads)
          outbound_payloads = []
          if test_case['outbound_newrelic_payloads']
            w3c_payloads.each do |w3c_payload|
              if newrelic_header = w3c_payload["newrelic"]
                outbound_payloads << DistributedTracePayload.from_http_safe(newrelic_header)
              else
                outbound_payloads << nil
              end
            end
          end
          outbound_payloads
        end

        def newrelic_key(key)
          const_name = "NewRelic::Agent::DistributedTracePayload::#{key.upcase}_KEY"
          Object.const_get(const_name)
        end

        def assign_not_nil_value(headers, key, value)
          return if value.nil?

          headers[newrelic_key(key)] = value
        end

        # builds a dotted hash version of newrelic header from its parsed json payload
        def add_newrelic_entries(payload, newrelic_header)
          return unless newrelic_header
          return unless newrelic_payload = DistributedTracePayload.from_http_safe(newrelic_header)

          payload["newrelic"] = {
            newrelic_key(:version) => newrelic_payload.version,
            newrelic_key(:data) => {}
          }
          data_payload = payload["newrelic"][newrelic_key(:data)]
          assign_not_nil_value(data_payload, :parent_type, newrelic_payload.parent_type)
          assign_not_nil_value(data_payload, :parent_account_id, newrelic_payload.parent_account_id)
          assign_not_nil_value(data_payload, :parent_app, newrelic_payload.parent_app_id)
          assign_not_nil_value(data_payload, :trusted_account, newrelic_payload.trusted_account_key)
          assign_not_nil_value(data_payload, :id, newrelic_payload.id)
          assign_not_nil_value(data_payload, :tx, newrelic_payload.transaction_id)
          assign_not_nil_value(data_payload, :trace_id, newrelic_payload.trace_id)
          assign_not_nil_value(data_payload, :sampled, newrelic_payload.sampled)
          assign_not_nil_value(data_payload, :timestamp, newrelic_payload.timestamp)
          assign_not_nil_value(data_payload, :priority, newrelic_payload.priority)
        end

        def create_payloads(test_case, txn)
          outbound_payloads = []
          payloads = Array(test_case['outbound_payloads'])

          [1, payloads.count].max.times do |index|
            outbound_headers = {}
            txn.distributed_tracer.append_payload(outbound_headers)
            txn.distributed_tracer.insert_headers(outbound_headers)
            outbound_payloads << outbound_headers
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

        ALLOWED_EVENT_TYPES = %w[ Transaction TransactionError Span ]

        def intrinsics_for_event(test_case, event_type)
          unless ALLOWED_EVENT_TYPES.include?(event_type)
            raise %Q(Test fixture refers to unexpected event type "#{event_type}")
          end

          return {} unless (intrinsics = test_case['intrinsics'])

          target_events = intrinsics['target_events'] || []
          return {} unless target_events.include?(event_type)

          common_intrinsics = intrinsics['common'] || {}
          event_intrinsics = intrinsics[event_type] || {}

          merge_intrinsics([common_intrinsics, event_intrinsics])
        end

        def verify_attributes(test_case_attributes, actual_attributes, event_type)
          if verbose_attributes?
            puts "", "*" * 80
            puts event_type
            pp(actual_attributes)
            puts "*" * 80
          end

          (test_case_attributes['exact'] || []).each do |k, v|
            assert_equal v,
              actual_attributes[k],
              %Q(Wrong "#{k}" #{event_type} attribute; expected #{v}, was #{actual_attributes[k]})
          end

          (test_case_attributes['notequal'] || []).each do |k, v|
            refute_equal(
              v,
              actual_attributes[k],
              "#{event_type} #{k} attribute should not equal #{v}"
            )
          end

          (test_case_attributes['expected'] || []).each do |key|
            assert actual_attributes.has_key?(key),
              %Q(Missing expected #{event_type} attribute "#{key}")
          end

          (test_case_attributes['unexpected'] || []).each do |key|
            refute actual_attributes.has_key?(key),
              %Q(Unexpected #{event_type} attribute "#{key}")
          end

          test_key = 'tracingVendors'
          actual_key = "tracestate.#{test_key}"

          if test_case_attributes.key?(test_key)
            vendors = Array(test_case_attributes[test_key]).join(',')

            assert_equal vendors, actual_attributes[actual_key],
              %Q(Wrong "#{test_key}" #{event_type} attribute; expected #{vendors}, was #{actual_attributes[actual_key]})
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

          harvested_events = NewRelic::Agent.agent.span_event_aggregator.harvest!
          last_span_events = harvested_events[1]

          refute_empty last_span_events, "no span events harvested!"

          actual_intrinsics = last_span_events[0][0]

          verify_attributes(test_case_intrinsics, actual_intrinsics, 'Span')
        end

        def verify_outbound_payloads(test_case, actual_payloads)
          return unless (test_case_payloads = test_case['outbound_payloads'])

          assert_equal test_case_payloads.count, actual_payloads.count

          test_case_payloads.zip(actual_payloads).each do |test_case_data, actual|
            context_hash = trace_context_headers_to_hash(actual)
            add_newrelic_entries(context_hash, actual["newrelic"])

            dotted_context_hash = NewRelic::Agent::Configuration::DottedHash.new(context_hash)
            stringified_hash = stringify_keys_in_object(dotted_context_hash)
            verify_attributes(test_case_data, stringified_hash, 'TraceContext Payload')
          end
        end

        def verify_metrics(test_case)
          expected_metrics = test_case['expected_metrics'].inject({}) do |memo, (metric_name, call_count)|
            memo[metric_name] = {call_count: call_count}
            memo
          end

          assert_metrics_recorded expected_metrics
        end

        def object_to_hash(object)
          object.instance_variables.inject({}) do |hash, variable_name|
            key = variable_name.to_s.sub(/^@/, '')
            hash[key] = object.instance_variable_get(variable_name)
            hash
          end
        end

        def trace_context_headers_to_hash(carrier)
          entry_key = NewRelic::Agent::Transaction::TraceContext::AccountHelpers.trace_state_entry_key
          header_data = TraceContext.parse( \
            carrier: carrier,
            trace_state_entry_key: entry_key
          )

          return {} unless header_data

          if header_data.trace_state_payload
            tracestate = {}
            tracestate_str = header_data.trace_state_payload.to_s
            tracestate_values = tracestate_str.split('-')

            tracestate['tenant_id'] = entry_key.sub('@nr', '')
            tracestate['version'] = tracestate_values[0]
            tracestate['parent_type'] = tracestate_values[1]
            tracestate['parent_account_id'] = tracestate_values[2]
            tracestate['parent_application_id'] = tracestate_values[3]
            tracestate['span_id'] = tracestate_values[4] unless tracestate_values[4].empty?
            tracestate['transaction_id'] = tracestate_values[5] unless tracestate_values[5].empty?
            tracestate['sampled'] = tracestate_values[6]
            tracestate['priority'] = tracestate_values[7].chomp("0")
            tracestate['timestamp'] = tracestate_values[8]
            tracestate['tracingVendors'] = header_data.trace_state_vendors
          else
            tracestate = nil
          end
          {
            'traceparent' => header_data.trace_parent,
            'tracestate' => tracestate
          }
        end

        def rack_format(test_case, carrier)
          carrier ||= {}
          rack_headers = {}
          rack_headers["HTTP_TRACEPARENT"] = carrier['traceparent'] if carrier['traceparent']
          rack_headers["HTTP_TRACESTATE"] = carrier['tracestate'] if carrier['tracestate']
          rack_headers["HTTP_NEWRELIC"] = carrier["newrelic"] if carrier["newrelic"]
          rack_headers
        end
      end
    end
  end
end
