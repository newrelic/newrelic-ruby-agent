# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    class Transaction
      module TraceContext
        include NewRelic::Coerce

        module AccountHelpers
          extend self

          def trace_state_entry_key
            @trace_state_entry_key ||= if Agent.config[:trusted_account_key]
              "#{Agent.config[:trusted_account_key]}@nr".freeze
            elsif Agent.config[:account_id]
              "#{Agent.config[:account_id]}@nr".freeze
            end
          end
        end

        SUPPORTABILITY_PREFIX = 'Supportability/TraceContext'
        CREATE_PREFIX = "#{SUPPORTABILITY_PREFIX}/Create"
        ACCEPT_PREFIX = "#{SUPPORTABILITY_PREFIX}/Accept"
        TRACESTATE_PREFIX = "#{SUPPORTABILITY_PREFIX}/TraceState"

        CREATE_SUCCESS_METRIC = "#{CREATE_PREFIX}/Success"
        CREATE_EXCEPTION_METRIC = "#{CREATE_PREFIX}/Exception"

        ACCEPT_SUCCESS_METRIC = "#{ACCEPT_PREFIX}/Success"
        ACCEPT_EXCEPTION_METRIC = "#{ACCEPT_PREFIX}/Exception"
        IGNORE_MULTIPLE_ACCEPT_METRIC = "#{ACCEPT_PREFIX}/Ignored/Multiple"
        IGNORE_ACCEPT_AFTER_CREATE_METRIC = "#{ACCEPT_PREFIX}/Ignored/CreateBeforeAccept"

        NO_NR_ENTRY_TRACESTATE_METRIC = "#{TRACESTATE_PREFIX}/NoNrEntry"
        INVALID_TRACESTATE_PAYLOAD_METRIC = "#{TRACESTATE_PREFIX}/InvalidNrEntry"

        attr_accessor :trace_context_header_data
        attr_reader :trace_state_payload

        def trace_parent_header_present?(request)
          request[NewRelic::HTTP_TRACEPARENT_KEY]
        end

        def accept_trace_context_incoming_request(request)
          header_data = NewRelic::Agent::DistributedTracing::TraceContext.parse(
            format: NewRelic::FORMAT_RACK,
            carrier: request,
            trace_state_entry_key: AccountHelpers.trace_state_entry_key
          )
          return if header_data.nil?

          accept_trace_context(header_data)
        end
        private :accept_trace_context_incoming_request

        def insert_trace_context_header(header, format = NewRelic::FORMAT_NON_RACK)
          return unless Agent.config[:'distributed_tracing.enabled']

          NewRelic::Agent::DistributedTracing::TraceContext.insert( \
            format: format,
            carrier: header,
            trace_id: transaction.trace_id.rjust(32, '0').downcase,
            parent_id: transaction.current_segment.guid,
            trace_flags: transaction.sampled? ? 0x1 : 0x0,
            trace_state: create_trace_state
          )

          @trace_context_inserted = true

          NewRelic::Agent.increment_metric(CREATE_SUCCESS_METRIC)
          true
        rescue Exception => e
          NewRelic::Agent.increment_metric(CREATE_EXCEPTION_METRIC)
          NewRelic::Agent.logger.warn('Failed to create trace context payload', e)
          false
        end

        def create_trace_state
          entry_key = AccountHelpers.trace_state_entry_key.dup
          payload = create_trace_state_payload

          if payload
            entry = NewRelic::Agent::DistributedTracing::TraceContext.create_trace_state_entry( \
              entry_key,
              payload.to_s
            )
          else
            entry = NewRelic::EMPTY_STR
          end

          trace_context_header_data ? trace_context_header_data.trace_state(entry) : entry
        end

        def create_trace_state_payload
          unless Agent.config[:'distributed_tracing.enabled']
            NewRelic::Agent.logger.warn('Not configured to create W3C trace context payload')
            return
          end

          span_guid = Agent.config[:'span_events.enabled'] ? transaction.current_segment.guid : nil
          transaction_guid = Agent.config[:'transaction_events.enabled'] ? transaction.guid : nil

          TraceContextPayload.create( \
            parent_account_id: Agent.config[:account_id],
            parent_app_id: Agent.config[:primary_application_id],
            transaction_id: transaction_guid,
            sampled: transaction.sampled?,
            priority: float!(transaction.priority, NewRelic::PRIORITY_PRECISION),
            id: span_guid
          )
        end

        def assign_trace_state_payload
          payload = @trace_context_header_data.trace_state_payload
          unless payload
            NewRelic::Agent.increment_metric(NO_NR_ENTRY_TRACESTATE_METRIC)
            return false
          end
          unless payload.valid?
            NewRelic::Agent.increment_metric(INVALID_TRACESTATE_PAYLOAD_METRIC)
            return false
          end
          @trace_state_payload = payload
        end

        def accept_trace_context(header_data)
          return if ignore_trace_context?

          @trace_context_header_data = header_data
          transaction.trace_id = header_data.trace_id
          transaction.parent_span_id = header_data.parent_id

          trace_flags = header_data.trace_parent['trace_flags']
          payload = assign_trace_state_payload

          if payload
            determine_sampling_decision(payload, trace_flags)
          else
            determine_sampling_decision(TraceContextPayload::INVALID, trace_flags)
            return false
          end

          transaction.distributed_tracer.parent_transaction_id = payload.transaction_id

          NewRelic::Agent.increment_metric(ACCEPT_SUCCESS_METRIC)
          true
        rescue => e
          NewRelic::Agent.increment_metric(ACCEPT_EXCEPTION_METRIC)
          NewRelic::Agent.logger.warn('Failed to accept trace context payload', e)
          false
        end

        def determine_sampling_decision(payload, trace_flags)
          if trace_flags == '01'
            set_priority_and_sampled(
              NewRelic::Agent.config[:'distributed_tracing.sampler.remote_parent_sampled'],
              NewRelic::Agent.config[:'distributed_tracing.sampler.remote_parent_sampled.trace_id_ratio_based.ratio'],
              payload,
              trace_flags
            )
          elsif trace_flags == '00'
            set_priority_and_sampled(
              NewRelic::Agent.config[:'distributed_tracing.sampler.remote_parent_not_sampled'],
              NewRelic::Agent.config[:'distributed_tracing.sampler.remote_parent_not_sampled.trace_id_ratio_based.ratio'],
              payload,
              trace_flags
            )
          else
            use_nr_tracestate_sampled(payload, trace_flags)
          end
        rescue
          use_nr_tracestate_sampled(payload, trace_flags)
        end

        def use_nr_tracestate_sampled(payload, trace_flags)
          if payload.sampled.nil?
            if trace_flags == '01'
              transaction.sampled = NewRelic::Agent.instance.adaptive_sampler_remote_parent_sampled.sampled?
            elsif trace_flags == '00'
              transaction.sampled = NewRelic::Agent.instance.adaptive_sampler_remote_parent_not_sampled.sampled?
            end

            transaction.priority = transaction.default_priority
          else
            transaction.sampled = payload.sampled
            transaction.priority = payload.priority if payload.priority
          end
        end

        def set_priority_and_sampled(sampler, ratio, payload, trace_flags = nil)
          case sampler
          when 'adaptive'
            use_nr_tracestate_sampled(payload, trace_flags)
          when 'always_on'
            transaction.sampled = true
            transaction.priority = 2.0
          when 'always_off'
            transaction.sampled = false
            transaction.priority = 0
          when 'trace_id_ratio_based'
            transaction.sampled = transaction.trace_ratio_sampled?(ratio)
            transaction.priority = transaction.default_priority
          end
        end

        def ignore_trace_context?
          if trace_context_header_data
            NewRelic::Agent.increment_metric(IGNORE_MULTIPLE_ACCEPT_METRIC)
            return true
          elsif trace_context_inserted?
            NewRelic::Agent.increment_metric(IGNORE_ACCEPT_AFTER_CREATE_METRIC)
            return true
          end
          false
        end

        def trace_context_inserted?
          @trace_context_inserted ||= false
        end
      end
    end
  end
end
