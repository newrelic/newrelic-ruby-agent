# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

require 'new_relic/agent/distributed_tracing/distributed_trace_payload'
require 'new_relic/agent/distributed_tracing/distributed_trace_intrinsics'
require 'new_relic/agent/distributed_tracing/distributed_trace_metrics'

module NewRelic
  module Agent
    class Transaction
      module TraceContext
        EMPTY_STRING                      = ''
        SUPPORTABILITY_PREFIX             = "Supportability/TraceContext"
        CREATE_PREFIX                     = "#{SUPPORTABILITY_PREFIX}/Create"
        ACCEPT_PREFIX                     = "#{SUPPORTABILITY_PREFIX}/Accept"
        TRACESTATE_PREFIX                 = "#{SUPPORTABILITY_PREFIX}/TraceState"
        
        CREATE_SUCCESS_METRIC             = "#{CREATE_PREFIX}/Success"
        CREATE_EXCEPTION_METRIC           = "#{CREATE_PREFIX}/Exception"
        
        ACCEPT_SUCCESS_METRIC             = "#{ACCEPT_PREFIX}/Success"
        ACCEPT_EXCEPTION_METRIC           = "#{ACCEPT_PREFIX}/Exception"
        IGNORE_MULTIPLE_ACCEPT_METRIC     = "#{ACCEPT_PREFIX}/Ignored/Multiple"
        IGNORE_ACCEPT_AFTER_CREATE_METRIC = "#{ACCEPT_PREFIX}/Ignored/CreateBeforeAccept"
        
        NO_NR_ENTRY_TRACESTATE_METRIC     = "#{TRACESTATE_PREFIX}/NoNrEntry"
        INVALID_TRACESTATE_PAYLOAD_METRIC = "#{TRACESTATE_PREFIX}/InvalidPayload"

        attr_accessor :trace_context_header_data
        attr_reader   :trace_state_payload

        def insert_trace_context \
            format: NewRelic::Agent::DistributedTracing::TraceContext::FORMAT_HTTP,
            carrier: nil
          
          return unless trace_context_active?
          NewRelic::Agent::DistributedTracing::TraceContext.insert \
            format: format,
            carrier: carrier,
            trace_id: transaction.trace_id,
            parent_id: transaction.current_segment.guid,
            trace_flags: transaction.sampled? ? 0x1 : 0x0,
            trace_state: create_trace_state
          @trace_context_inserted = true
          NewRelic::Agent.increment_metric CREATE_SUCCESS_METRIC
          true
        rescue Exception => e
          NewRelic::Agent.increment_metric CREATE_EXCEPTION_METRIC
          NewRelic::Agent.logger.warn "Failed to create trace context payload", e
          false
        end

        def create_trace_state
          entry_key = NewRelic::Agent::DistributedTracing::TraceContext::AccountHelpers.trace_state_entry_key
          payload = create_trace_state_payload

          if payload
            entry = NewRelic::Agent::DistributedTracing::TraceContext.create_trace_state_entry \
              entry_key,
              payload.to_s
          else
            entry = EMPTY_STRING
          end

          trace_context_header_data ? trace_context_header_data.trace_state(entry) : entry
        end

        def create_trace_state_payload
          unless trace_context_enabled?
            NewRelic::Agent.logger.warn "Not configured to create WC3 trace context payload"
            return
          end

          if Agent.config[:'span_events.enabled']
            TraceContextPayload.create \
              parent_account_id: Agent.config[:account_id],
              parent_app_id: Agent.config[:primary_application_id],
              transaction_id: transaction.guid,
              sampled: transaction.sampled?,
              priority: transaction.priority,
              id: transaction.current_segment.guid
          elsif trace_context_header_data
            trace_context_header_data.trace_state_payload
          end
        end

        def assign_trace_state_payload
          payload = @trace_context_header_data.trace_state_payload
          unless payload
            NewRelic::Agent.increment_metric NO_NR_ENTRY_TRACESTATE_METRIC
            return false
          end
          unless payload.valid?
            NewRelic::Agent.increment_metric INVALID_TRACESTATE_PAYLOAD_METRIC
            return false
          end            
          @trace_state_payload = payload
        end

        def accept_trace_context header_data
          unless trace_context_enabled?
            NewRelic::Agent.logger.warn "Not configured to accept WC3 trace context payload"
            return false
          end
          return false if ignore_trace_context?
          
          @trace_context_header_data = header_data
          transaction.instance_variable_set :@trace_id, header_data.trace_id
          transaction.instance_variable_set :@parent_span_id, header_data.parent_id

          return false unless payload = assign_trace_state_payload

          transaction.instance_variable_set :@parent_transaction_id, payload.transaction_id

          unless payload.sampled.nil?
            transaction.sampled = payload.sampled
            transaction.priority = payload.priority if payload.priority
          end
          NewRelic::Agent.increment_metric ACCEPT_SUCCESS_METRIC
          true
        rescue => e
          NewRelic::Agent.increment_metric ACCEPT_EXCEPTION_METRIC
          NewRelic::Agent.logger.warn "Failed to accept trace context payload", e
          false
        end

        def append_trace_context_info transaction_payload
          return unless trace_context_active?
          DistributedTraceIntrinsics.copy_from_transaction \
              transaction,
              trace_state_payload,
              transaction_payload
        end

        def ignore_trace_context?
          if trace_context_header_data
            NewRelic::Agent.increment_metric IGNORE_MULTIPLE_ACCEPT_METRIC
            return true
          elsif trace_context_inserted?
            NewRelic::Agent.increment_metric IGNORE_ACCEPT_AFTER_CREATE_METRIC
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
