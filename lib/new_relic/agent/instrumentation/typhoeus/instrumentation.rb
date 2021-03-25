# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

module NewRelic
  module Agent
    module Instrumentation
      module Typhoeus

        HYDRA_SEGMENT_NAME    = "External/Multiple/Typhoeus::Hydra/run"
        NOTICIBLE_ERROR_CLASS = "Typhoeus::Errors::TyphoeusError"

        EARLIEST_VERSION = Gem::Version.new("0.5.3")

        def self.is_supported_version?
          Gem::Version.new(::Typhoeus::VERSION) >= EARLIEST_VERSION
        end

        def self.request_is_hydra_enabled?(request)
          request.respond_to?(:hydra) && request.hydra
        end

        def self.response_message(response)
          if response.respond_to?(:response_message)
            response.response_message
          elsif response.respond_to?(:return_message)
            response.return_message
          else
            # 0.5.4 seems to have lost xxxx_message methods altogether.
            "timeout" 
          end
        end

        def with_tracing
          segment = NewRelic::Agent::Tracer.start_segment name: HYDRA_SEGMENT_NAME
          instance_variable_set :@__newrelic_hydra_segment, segment
          begin
            yield
          ensure
            segment.finish if segment
          end
        end

        def self.trace(request)
          state = NewRelic::Agent::Tracer.state
          return unless state.is_execution_traced?

          wrapped_request = ::NewRelic::Agent::HTTPClients::TyphoeusHTTPRequest.new(request)

          parent = if request_is_hydra_enabled?(request)
            request.hydra.instance_variable_get(:@__newrelic_hydra_segment)
          end

          segment = NewRelic::Agent::Tracer.start_external_request_segment(
            library: wrapped_request.type,
            uri: wrapped_request.uri,
            procedure: wrapped_request.method,
            parent: parent
          )

          segment.add_request_headers wrapped_request

          callback = Proc.new do
            wrapped_response = HTTPClients::TyphoeusHTTPResponse.new(request.response)

            segment.process_response_headers wrapped_response

            if request.response.code == 0
              segment.notice_error NoticibleError.new NOTICIBLE_ERROR_CLASS, response_message(request.response)
            end
           
            segment.finish if segment
          end
          request.on_complete.unshift(callback)

        rescue => e
          NewRelic::Agent.logger.error("Exception during trace setup for Typhoeus request", e)
        end
      end
    end
  end
end
