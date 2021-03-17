# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.


module NewRelic::Agent::Instrumentation
  module HTTPClient
    module Prepend 
      def do_get_block(req, proxy, conn, &block)
        wrapped_request = NewRelic::Agent::HTTPClients::HTTPClientRequest.new(req)
        segment = NewRelic::Agent::Tracer.start_external_request_segment(
          library: wrapped_request.type,
          uri: wrapped_request.uri,
          procedure: wrapped_request.method
        )

        begin
          response = nil
          segment.add_request_headers wrapped_request

          NewRelic::Agent::Tracer.capture_segment_error segment do
            super
          end
          response = conn.pop
          conn.push response

          wrapped_response = ::NewRelic::Agent::HTTPClients::HTTPClientResponse.new(response)
          segment.process_response_headers wrapped_response

          response
        ensure
          segment.finish if segment
        end
      end
    end
  end
end

