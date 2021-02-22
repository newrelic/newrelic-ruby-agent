# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

module NewRelic::Agent::Instrumentation
  module NetHTTP
    module Chain
      def self.instrument!
        Net::HTTP.class_eval do
          def request_with_newrelic_trace(request, *args, &block)
            wrapped_request = NewRelic::Agent::HTTPClients::NetHTTPRequest.new(self, request)
    
            segment = NewRelic::Agent::Tracer.start_external_request_segment(
              library: wrapped_request.type,
              uri: wrapped_request.uri,
              procedure: wrapped_request.method
            )
    
            begin
              response = nil
              segment.add_request_headers wrapped_request
    
              # RUBY-1244 Disable further tracing in request to avoid double
              # counting if connection wasn't started (which calls request again).
              NewRelic::Agent.disable_all_tracing do
                response = NewRelic::Agent::Tracer.capture_segment_error segment do
                  request_without_newrelic_trace(request, *args, &block)
                end
              end
    
              wrapped_response = NewRelic::Agent::HTTPClients::NetHTTPResponse.new response
              segment.process_response_headers wrapped_response
              response
            ensure
              segment.finish
            end
          end  
    
          alias request_without_newrelic_trace request
          alias request request_with_newrelic_trace
        end
      end
    end
  end
end