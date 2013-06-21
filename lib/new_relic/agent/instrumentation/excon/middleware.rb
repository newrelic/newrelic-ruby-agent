# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module ::Excon
  module Middleware
    class NewRelicCrossAppTracing
      def initialize(stack)
        @stack = stack
      end

      def request_call(datum)
        begin
          wrapped_request = ::NewRelic::Agent::HTTPClients::ExconHTTPRequest.new(datum)
          t0, segment = ::NewRelic::Agent::CrossAppTracing.start_trace(wrapped_request)
          datum[:newrelic_trace_data] = [t0, segment, wrapped_request]
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

      def finish_trace(datum)
        trace_data = datum.delete(:newrelic_trace_data)
        if trace_data
          t0, segment, wrapped_request = trace_data
          if datum[:response]
            wrapped_response = ::NewRelic::Agent::HTTPClients::ExconHTTPResponse.new(datum[:response])
          end
          ::NewRelic::Agent::CrossAppTracing.finish_trace(t0, segment, wrapped_request, wrapped_response)
        end
      end
    end
  end
end
