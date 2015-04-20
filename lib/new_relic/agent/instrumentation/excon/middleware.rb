# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module ::Excon
  module Middleware
    class NewRelicCrossAppTracing
      TRACE_DATA_IVAR = :@newrelic_trace_data

      def initialize(stack)
        @stack = stack
      end

      def request_call(datum) #THREAD_LOCAL_ACCESS
        begin
          # Only instrument this request if we haven't already done so, because
          # we can get request_call multiple times for requests marked as
          # :idempotent in the options, but there will be only a single
          # accompanying response_call/error_call.
          if datum[:connection] && !datum[:connection].instance_variable_get(TRACE_DATA_IVAR)
            wrapped_request = ::NewRelic::Agent::HTTPClients::ExconHTTPRequest.new(datum)
            state   = ::NewRelic::Agent::TransactionState.tl_get
            t0      = Time.now
            node = ::NewRelic::Agent::CrossAppTracing.start_trace(state, t0, wrapped_request)
            datum[:connection].instance_variable_set(TRACE_DATA_IVAR, [t0, node, wrapped_request])
          end
        rescue => e
          NewRelic::Agent.logger.debug(e)
        end
        @stack.request_call(datum)
      end

      def response_call(datum)
        finish_trace(datum)
        @stack.response_call(datum)
      end

      def error_call(datum)
        finish_trace(datum)
        @stack.error_call(datum)
      end

      def finish_trace(datum) #THREAD_LOCAL_ACCESS
        trace_data = datum[:connection] && datum[:connection].instance_variable_get(TRACE_DATA_IVAR)
        if trace_data
          datum[:connection].instance_variable_set(TRACE_DATA_IVAR, nil)
          t0, node, wrapped_request = trace_data
          if datum[:response]
            wrapped_response = ::NewRelic::Agent::HTTPClients::ExconHTTPResponse.new(datum[:response])
          end
          state = ::NewRelic::Agent::TransactionState.tl_get
          ::NewRelic::Agent::CrossAppTracing.finish_trace(state, t0, node, wrapped_request, wrapped_response)
        end
      end
    end
  end
end
