# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

module NewRelic
  module Agent
    module Instrumentation
      module NetHTTP
        def request_with_tracing(request)
          wrapped_request = NewRelic::Agent::HTTPClients::NetHTTPRequest.new(self, request)
          # NewRelic::Agent.logger.debug("=====WALUIGI threadid: #{::Thread.current.object_id} //in net http request_with_tracing wrapped_request: #{wrapped_request.inspect}")

          segment = NewRelic::Agent::Tracer.start_external_request_segment(
            library: wrapped_request.type,
            uri: wrapped_request.uri,
            procedure: wrapped_request.method
          )
          # NewRelic::Agent.logger.debug("=====WALUIGI threadid: #{::Thread.current.object_id} //in net http request_with_tracing segment id: #{segment&.guid}")

          begin
            response = nil
            segment.add_request_headers wrapped_request

            # RUBY-1244 Disable further tracing in request to avoid double
            # counting if connection wasn't started (which calls request again).
            NewRelic::Agent.disable_all_tracing do
              response = NewRelic::Agent::Tracer.capture_segment_error segment do
                yield
              end
            end

            wrapped_response = NewRelic::Agent::HTTPClients::NetHTTPResponse.new response
            segment.process_response_headers wrapped_response
            response
          ensure
            # NewRelic::Agent.logger.debug("=====WALUIGI threadid: #{::Thread.current.object_id} //in net http request_with_tracing ensure segment id: #{segment&.guid}")
            segment.finish
          end
        end
      end
    end
  end
end
