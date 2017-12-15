# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

DependencyDetection.defer do
  named :typhoeus

  depends_on do
    defined?(Typhoeus) && defined?(Typhoeus::VERSION)
  end

  depends_on do
    NewRelic::Agent::Instrumentation::TyphoeusTracing.is_supported_version?
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Typhoeus instrumentation'
    require 'new_relic/agent/cross_app_tracing'
    require 'new_relic/agent/http_clients/typhoeus_wrappers'
  end

  # Basic request tracing
  executes do
    Typhoeus.before do |request|
      NewRelic::Agent::Instrumentation::TyphoeusTracing.trace(request)

      # Ensure that we always return a truthy value from the before block,
      # otherwise Typhoeus will bail out of the instrumentation.
      true
    end
  end

  # Apply single TT node for Hydra requests until async support
  executes do
    class Typhoeus::Hydra

      def run_with_newrelic(*args)
        segment = NewRelic::Agent::Transaction.start_segment(
          name: NewRelic::Agent::Instrumentation::TyphoeusTracing::HYDRA_SEGMENT_NAME
        )

        instance_variable_set :@__newrelic_hydra_segment, segment

        begin
          run_without_newrelic(*args)
        ensure
          segment.finish if segment
        end
      end

      alias run_without_newrelic run
      alias run run_with_newrelic
    end
  end
end


module NewRelic
  module Agent
    module Instrumentation
      module TyphoeusTracing

        HYDRA_SEGMENT_NAME = "External/Multiple/Typhoeus::Hydra/run"

        EARLIEST_VERSION = Gem::Version.new("0.5.3")

        def self.is_supported_version?
          Gem::Version.new(Typhoeus::VERSION) >= NewRelic::Agent::Instrumentation::TyphoeusTracing::EARLIEST_VERSION
        end

        def self.request_is_hydra_enabled?(request)
          request.respond_to?(:hydra) && request.hydra
        end

        def self.trace(request)
          state = NewRelic::Agent::TransactionState.tl_get
          return unless state.is_execution_traced?

          wrapped_request = ::NewRelic::Agent::HTTPClients::TyphoeusHTTPRequest.new(request)

          parent = if request_is_hydra_enabled?(request)
            request.hydra.instance_variable_get(:@__newrelic_hydra_segment)
          end

          segment = NewRelic::Agent::Transaction.start_external_request_segment(
            library: wrapped_request.type,
            uri: wrapped_request.uri,
            procedure: wrapped_request.method,
            parent: parent
          )

          segment.add_request_headers wrapped_request

          callback = Proc.new do
            wrapped_response = ::NewRelic::Agent::HTTPClients::TyphoeusHTTPResponse.new(request.response)
            segment.read_response_headers wrapped_response
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
