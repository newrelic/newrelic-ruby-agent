# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module AsyncHttp
    # from the async http doumentation:
    # @parameter method [String] The request method, e.g. `GET`.
    # @parameter url [String] The URL to request, e.g. `https://www.codeotaku.com`.
    # @parameter headers [Hash | Protocol::HTTP::Headers] The headers to send with the request.
    # @parameter body [String | Protocol::HTTP::Body] The body to send with the request.

    # but their example has headers being an array??? weird, ig lets make sure we work ok with that
    # like [[:content_type, "application/json"], [:accept, "application/json"]
    def call_with_new_relic(method, url, headers = nil, body = nil)
      headers ||= {} # if it is nil, we need to make it a hash so we can insert headers
      wrapped_request = NewRelic::Agent::HTTPClients::AsyncHTTPRequest.new(self, method, url, headers)

      segment = NewRelic::Agent::Tracer.start_external_request_segment(
        library: wrapped_request.type,
        uri: wrapped_request.uri,
        procedure: wrapped_request.method
      )

      begin
        response = nil
        segment.add_request_headers(wrapped_request)

        NewRelic::Agent.disable_all_tracing do
          response = NewRelic::Agent::Tracer.capture_segment_error(segment) do
            yield(headers)
          end
        end

        wrapped_response = NewRelic::Agent::HTTPClients::AsyncHTTPResponse.new(response)
        segment.process_response_headers(wrapped_response)
        response
      ensure
        segment&.finish
      end
    end
  end
end
