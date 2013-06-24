# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

DependencyDetection.defer do
  named :typhoeus

  depends_on do
    defined?(Typhoeus) && defined?(Typhoeus::VERSION)
  end

  depends_on do
    Typhoeus::VERSION >= NewRelic::Agent::Instrumentation::TyphoeusTracing::EARLIEST_VERSION
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Typhoeus instrumentation'
    require 'new_relic/agent/cross_app_tracing'
    require 'new_relic/agent/http_clients/typhoeus_wrappers'
  end

  # Basic request tracing
  executes do
    if Typhoeus::VERSION >= "0.5.0"
      Typhoeus.before do |request|
        NewRelic::Agent::Instrumentation::TyphoeusTracing.trace(request)

        # Ensure that we always return a truthy value from the before block,
        # otherwise Typhoeus will bail out of the instrumentation.
        true
      end
    else
      # The Typhoeus.before hook that we want to use was only introduced in
      # the 0.5.x version. On older versions, we rely on the use of
      # Typhoeus::Hydra internally to get hold of the request to trace.
      class Typhoeus::Request
        class << self
          def run_with_newrelic(url, params)
            original_single_request = Typhoeus::Hydra.hydra.newrelic_single_request
            Typhoeus::Hydra.hydra.newrelic_single_request = true

            run_without_newrelic(url, params)
          ensure
            Typhoeus::Hydra.hydra.newrelic_single_request = original_single_request
          end

          alias run_without_newrelic run
          alias run run_with_newrelic
        end
      end

      class Typhoeus::Hydra
        def queue_with_newrelic(request, *args)
          NewRelic::Agent::Instrumentation::TyphoeusTracing.trace(request) if newrelic_single_request
          queue_without_newrelic(request, *args)
        end

        alias queue_without_newrelic queue
        alias queue queue_with_newrelic
      end
    end
  end

  # Apply single TT node for Hydra requests until async support
  executes do
    class Typhoeus::Hydra
      include NewRelic::Agent::MethodTracer

      attr_accessor :newrelic_single_request

      # There are two supported paths by which we may arrive here in Typhoeus::Hyrda#run:
      #
      # Via a single request made via Typhoeus::Request, like this:
      #
      #   1. A class method on Typhoues::Request (e.g. #get, #post, etc) is invoked
      #   2. The class method calls through to the aliased Typhoeus::Request.run
      #   3. The aliased Typhoeus::Request.run sets the newrelic_single_request
      #      flag on the global shared Hydra instance
      #   4. Inside the original Typhoeus::Request.run, a Typhoeus::Request
      #      instance is created
      #   5. The instance is enqueued on the global shared Hydra instance,
      #      hitting our aliased Typhoeus::Hydra#queue
      #   6. In the aliased Typhoeus::Hydra#queue, we call
      #      NewRelic::Agent::Instrumentation::TyphoeusTracing.trace to setup
      #      the tracing
      #   7. The original Typhoeus::Request.run calls the aliased
      #      Typhoeus::Hydra#run on the global shared Hydra instance
      #   8. In the aliased Typhoeus::Hydra#run, we see that
      #      newrelic_single_request is set, and call through to the original
      #      implementation.
      #
      # Via a batch of parallel requests made through an explicit call to
      # Typhoeus::Hydra#run, like this:
      #
      #   1. One or more Typhoeus::Request objects are explicitly created
      #   2. As the Request objects are enqueued with the Hydra instance, they
      #      pass through our aliased Typhoeus::Hydra#queue, but this is
      #      effectively a no-op because the newrelic_single_request flag is not
      #      set.
      #   3. Typhoeus::Hydra.run is explicitly called, and we hit the
      #      trace_execution_scoped path in our aliased version, again because
      #      newrelic_single_request is not set.
      #
      # ... and of course, all of this noise is made irrelevant in later versions
      # of Typhoeus by the addition of the Typhoeus.before hook.
      #
      def run_with_newrelic(*args)
        if newrelic_single_request
          run_without_newrelic(*args)
        else
          trace_execution_scoped("External/Multiple/Typhoeus::Hydra/run") do
            run_without_newrelic(*args)
          end
        end
      end

      alias run_without_newrelic run
      alias run run_with_newrelic
    end
  end
end


module NewRelic::Agent::Instrumentation::TyphoeusTracing

  EARLIEST_VERSION = "0.2.0"

  def self.request_is_hydra_enabled?(request)
    request.respond_to?(:hydra) && request.hydra
  end

  def self.trace(request)
    if NewRelic::Agent.is_execution_traced? && !request_is_hydra_enabled?(request)
      wrapped_request = ::NewRelic::Agent::HTTPClients::TyphoeusHTTPRequest.new(request)
      t0, segment = ::NewRelic::Agent::CrossAppTracing.start_trace(wrapped_request)
      request.on_complete do
        wrapped_response = ::NewRelic::Agent::HTTPClients::TyphoeusHTTPResponse.new(request.response)
        ::NewRelic::Agent::CrossAppTracing.finish_trace(t0, segment, wrapped_request, wrapped_response)
      end if t0
    end
  end
end
