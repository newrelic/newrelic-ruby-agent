# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module Instrumentation
      module NetHTTP
        INSTRUMENTATION_NAME = NewRelic::Agent.base_name(name)

        def request_with_tracing(request)
          NewRelic::Agent.record_instrumentation_invocation(INSTRUMENTATION_NAME)

          wrapped_request = NewRelic::Agent::HTTPClients::NetHTTPRequest.new(self, request)

          segment = NewRelic::Agent::Tracer.start_external_request_segment(
            library: wrapped_request.type,
            uri: wrapped_request.uri,
            procedure: wrapped_request.method
          )

          begin
            response = nil
            segment.add_request_headers(wrapped_request)

            # RUBY-1244 Disable further tracing in request to avoid double
            # counting if connection wasn't started (which calls request again).
            NewRelic::Agent.disable_all_tracing do
              response = NewRelic::Agent::Tracer.capture_segment_error(segment) do
                yield
              end
            end

            wrapped_response = NewRelic::Agent::HTTPClients::NetHTTPResponse.new(response)
            add_llm_response_headers(wrapped_response, segment.parent) if llm_parent?(segment)
            segment.process_response_headers(wrapped_response)
            response
          ensure
            segment&.finish
          end
        end

        def llm_parent?(segment)
          segment&.parent&.name&.match?(/Llm\/.*\/OpenAI\/create/)
        end

        def add_llm_response_headers(response, parent)
          # binding.irb
          return unless parent.instance_variable_defined?(:@chat_completion_summary) # and maybe log a warning??

          event = parent.chat_completion_summary
          event.request_id = response[NewRelic::Agent::Llm::LlmEvent::X_REQUEST_ID] # every event needs this, maybe we should move it someplace else?
          event.populate_openai_response_headers(response.to_hash)
        end
      end
    end
  end
end
