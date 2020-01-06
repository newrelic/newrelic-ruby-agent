# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require_relative 'monitors/inbound_request_monitor'

require_relative 'monitors/synthetics_monitor'

require_relative 'monitors/cross_app_monitor'
require_relative 'monitors/distributed_trace_monitor'
require_relative 'monitors/trace_context_request_monitor'

module NewRelic
  module Agent
    class Monitors
      attr_reader :cross_app_monitor

      def initialize events
        @synthetics_monitor        = NewRelic::Agent::SyntheticsMonitor.new events
      
        @cross_app_monitor         = NewRelic::Agent::CrossAppMonitor.new events
        @distributed_trace_monitor = NewRelic::Agent::DistributedTraceMonitor.new events
        @trace_context_monitor     = NewRelic::Agent::DistributedTracing::TraceContextRequestMonitor.new events
      end

      def insert_distributed_tracing_headers transaction, request
        if transaction.trace_context_enabled?
          insert_trace_context_headers transaction, request
        elsif transaction.nr_distributed_tracing_enabled?
          insert_distributed_trace_header transaction, request
        elsif CrossAppTracing.cross_app_enabled?
          insert_cross_app_header transaction, request
        end
      end

      private 

      def insert_cross_app_header transaction, request
        transaction.is_cross_app_caller = true
        txn_guid = transaction.guid
        trip_id   = transaction && transaction.cat_trip_id
        path_hash = transaction && transaction.cat_path_hash

        CrossAppTracing.insert_request_headers request, txn_guid, trip_id, path_hash
      end

      def insert_trace_context_headers transaction, request
        transaction.insert_trace_context carrier: request
      end

      NEWRELIC_TRACE_HEADER = "newrelic".freeze

      def insert_distributed_trace_header transaction, request
        payload = transaction.create_distributed_trace_payload
        request[NEWRELIC_TRACE_HEADER] = payload.http_safe if payload
      end

    end
  end
end