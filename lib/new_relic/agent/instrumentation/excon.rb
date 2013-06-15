# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

DependencyDetection.defer do
  @name = :excon

  depends_on do
    defined?(::Excon) && !NewRelic::Agent.config[:disable_excon]
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Excon instrumentation'
    require 'new_relic/agent/cross_app_tracing'
    require 'new_relic/agent/http_clients/excon_wrappers'
  end

  executes do
    module ::Excon
      module Middleware
        class NewRelicCrossAppTracing < Excon::Middleware::Base
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
              else
                wrapped_response = nil
              end
              ::NewRelic::Agent::CrossAppTracing.finish_trace(t0, segment, wrapped_request, wrapped_response)
            end
          end
        end
      end
    end

    defaults = Excon.defaults
    defaults[:middlewares] << ::Excon::Middleware::NewRelicCrossAppTracing
    Excon.defaults = defaults
  end
end
