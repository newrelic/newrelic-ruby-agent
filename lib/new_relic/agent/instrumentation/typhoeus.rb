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
      include NewRelic::Agent::MethodTracer

      def run_with_newrelic(*args)
        trace_execution_scoped("External/Multiple/Typhoeus::Hydra/run") do
          run_without_newrelic(*args)
        end
      end

      alias run_without_newrelic run
      alias run run_with_newrelic
    end
  end
end


module NewRelic::Agent::Instrumentation::TyphoeusTracing

  EARLIEST_VERSION = NewRelic::VersionNumber.new("0.5.3")

  def self.is_supported_version?
    NewRelic::VersionNumber.new(Typhoeus::VERSION) >= NewRelic::Agent::Instrumentation::TyphoeusTracing::EARLIEST_VERSION
  end

  def self.request_is_hydra_enabled?(request)
    request.respond_to?(:hydra) && request.hydra
  end

  def self.trace(request)
    state = NewRelic::Agent::TransactionState.tl_get
    if state.is_execution_traced? && !request_is_hydra_enabled?(request)
      wrapped_request = ::NewRelic::Agent::HTTPClients::TyphoeusHTTPRequest.new(request)
      t0 = Time.now
      node = ::NewRelic::Agent::CrossAppTracing.start_trace(state, t0, wrapped_request)
      callback = Proc.new do
        wrapped_response = ::NewRelic::Agent::HTTPClients::TyphoeusHTTPResponse.new(request.response)
        ::NewRelic::Agent::CrossAppTracing.finish_trace(state, t0, node, wrapped_request, wrapped_response)
      end
      request.on_complete.unshift(callback)
    end
  rescue => e
    NewRelic::Agent.logger.error("Exception during trace setup for Typhoeus request", e)
  end
end
