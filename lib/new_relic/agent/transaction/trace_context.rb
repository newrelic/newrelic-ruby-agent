# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require 'new_relic/agent/trace_context'
require 'new_relic/agent/distributed_trace_payload'
require 'new_relic/agent/distributed_trace_intrinsics'
require 'new_relic/agent/distributed_trace_metrics'

module NewRelic
  module Agent
    class Transaction
      attr_accessor :trace_context_header_data
      attr_writer   :trace_context_inserted
      attr_reader   :trace_state_payload

      module TraceContext

        SUPPORTABILITY_CREATE_SUCCESS = "Supportability/TraceContext/Create/Success".freeze
        SUPPORTABILITY_CREATE_EXCEPTION = "Supportability/TraceContext/Create/Exception".freeze
        SUPPORTABILITY_ACCEPT_SUCCESS = "Supportability/TraceContext/Accept/Success".freeze
        SUPPORTABILITY_ACCEPT_EXCEPTION = "Supportability/TraceContext/Accept/Exception".freeze
        SUPPORTABILITY_MULTIPLE_ACCEPT_TRACE_CONTEXT = "Supportability/TraceContext/Accept/Ignored/Multiple".freeze
        SUPPORTABILITY_CREATE_BEFORE_ACCEPT_TRACE_CONTEXT = "Supportability/TraceContext/Accept/Ignored/CreateBeforeAccept".freeze

        def insert_trace_context \
            format: NewRelic::Agent::TraceContext::FORMAT_HTTP,
            carrier: nil
          return unless trace_context_enabled?
          NewRelic::Agent::TraceContext.insert \
            format: format,
            carrier: carrier,
            trace_id: trace_id,
            parent_id: current_segment.guid,
            trace_flags: sampled? ? 0x1 : 0x0,
            trace_state: create_trace_state
          self.trace_context_inserted = true
          NewRelic::Agent.increment_metric SUPPORTABILITY_CREATE_SUCCESS
          true
        rescue Exception => e
          NewRelic::Agent.increment_metric SUPPORTABILITY_CREATE_EXCEPTION
          NewRelic::Agent.logger.warn "Failed to create trace context payload", e
          false
        end

        def create_trace_state
          entry_key = NewRelic::Agent::TraceContext::AccountHelpers.trace_state_entry_key
          payload = create_trace_state_payload
          entry = NewRelic::Agent::TraceContext.create_trace_state_entry \
            entry_key,
            payload.to_s

          trace_context_header_data ? trace_context_header_data.trace_state(entry) : entry
        end

        def create_trace_state_payload
          return unless trace_context_enabled?

          payload = TraceContextPayload.create \
            parent_account_id:  Agent.config[:account_id],
            parent_app_id:  Agent.config[:primary_application_id],
            transaction_id:  guid,
            sampled:  sampled?,
            priority:  priority

          if Agent.config[:'span_events.enabled'] && sampled?
            payload.id = current_segment.guid
          end

          payload
        end


        def accept_trace_context trace_context_header_data
          return unless trace_context_enabled?
          return false if check_trace_context_ignored
          return false unless @trace_context_header_data = trace_context_header_data
          @trace_id = @trace_context_header_data.trace_id

          return false unless payload = trace_context_header_data.trace_state_payload
          return false unless payload.valid?
          @trace_state_payload = payload

          @parent_transaction_id = payload.transaction_id

          unless payload.sampled.nil?
            self.sampled = payload.sampled
            self.priority = payload.priority if payload.priority
          end
          NewRelic::Agent.increment_metric SUPPORTABILITY_ACCEPT_SUCCESS
          true
        rescue => e
          NewRelic::Agent.increment_metric SUPPORTABILITY_ACCEPT_EXCEPTION
          NewRelic::Agent.logger.warn "Failed to accept trace context payload", e
          false
        end

        def append_trace_context_info transaction_payload
          return unless trace_context_enabled?
          DistributedTraceIntrinsics.copy_from_transaction \
              self,
              @trace_state_payload,
              transaction_payload
        end

        def record_trace_context_metrics
          return unless trace_context_enabled?

          DistributedTraceMetrics.record_metrics_for_transaction self
        end

        SUPPORTABILITY_MULTIPLE_ACCEPT_TRACE_CONTEXT = "Supportability/TraceContext/AcceptPayload/Ignored/Multiple".freeze
        SUPPORTABILITY_CREATE_BEFORE_ACCEPT_TRACE_CONTEXT = "Supportability/TraceContext/AcceptPayload/Ignored/CreateBeforeAccept".freeze

        def check_trace_context_ignored
          if trace_context_header_data
            NewRelic::Agent.increment_metric SUPPORTABILITY_MULTIPLE_ACCEPT_TRACE_CONTEXT
            return true
          elsif trace_context_inserted?
            NewRelic::Agent.increment_metric SUPPORTABILITY_CREATE_BEFORE_ACCEPT_TRACE_CONTEXT
            return true
          end
          false
        end
      end

      def trace_context_inserted?
        @trace_context_inserted ||=  false
      end

      def trace_context_enabled?
        Agent.config[:'trace_context.enabled'] && Agent.instance.connected?
      end

    end
  end
end
