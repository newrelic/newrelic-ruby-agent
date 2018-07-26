# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/distributed_trace_payload'

module NewRelic
  module Agent
    #
    # This module contains helper methods related to Distributed
    # Tracing, an APM feature that ties together traces from multiple
    # apps in one view.  Use it to add distributed tracing to protocols
    # not already supported by the agent.
    #
    # @api public
    module DistributedTracing
      extend self

      # Create a payload object containing the current transaction's
      # tracing properties (e.g., duration, priority).  You can use
      # this object to generate headers to inject into a network
      # request, so that the downstream service can participate in a
      # distributed trace.
      #
      # @return [DistributedTracePayload] Payload for the current
      #                                   transaction, or +nil+ if we
      #                                   could not create the payload
      #
      # @api public
      def create_distributed_trace_payload
        if transaction = Transaction.tl_current
          transaction.create_distributed_trace_payload
        end
      rescue => e
        NewRelic::Agent.logger.error 'error during create_distributed_trace_payload', e
        nil
      end

      # Decode a JSON string containing distributed trace properties
      # (e.g., calling application, priority) and apply them to the
      # current transaction.  You can use it to receive distributed
      # tracing information protocols the agent does not already
      # support.
      #
      # This method will fail if you call it after calling
      # {#create_distributed_trace_payload}.
      #
      # @param payload [String] Incoming distributed trace payload,
      #                         either as a JSON string or as a
      #                         header-friendly string returned from
      #                         {DistributedTracePayload#http_safe}
      #
      # @return nil
      #
      # @api public
      def accept_distributed_trace_payload payload
        if transaction = Transaction.tl_current
          transaction.accept_distributed_trace_payload(payload)
        end
        nil
      rescue => e
        NewRelic::Agent.logger.error 'error during accept_distributed_trace_payload', e
        nil
      end
    end
  end
end
