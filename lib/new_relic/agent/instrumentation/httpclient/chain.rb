# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

module NewRelic::Agent::Instrumentation
  module HTTPClient
    module Chain 
      def self.instrument!
        ::HTTPClient.class_eval do
          def do_get_block_with_newrelic(req, proxy, conn, &block)
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
                do_get_block_without_newrelic(req, proxy, conn, &block)
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
    
          alias :do_get_block_without_newrelic :do_get_block
          alias :do_get_block :do_get_block_with_newrelic
        end
      end
    end
  end
end

