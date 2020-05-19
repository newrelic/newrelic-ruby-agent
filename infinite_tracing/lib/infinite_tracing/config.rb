# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent
  module InfiniteTracing
    module Config
      extend self

      TRACE_OBSERVER_NOT_CONFIGURED_ERROR = "Trace Observer host not configured!"

      # We only want to load the infinite tracing gem's files when
      #   a) we're inside test framework and running tests
      #   b) the trace observer host is configured
      #
      def should_load?
        test_framework? || trace_observer_configured?
      end

      # Infinite Tracing support is enabled when the following conditions are true:
      #   a) Distributed tracing is enabled in the agent, AND
      #   b) Span events are enabled in the agent, both by client side configuration
      #      AND the collect_span_events connect response field, AND
      #   c) A Trace Observer host is configured by setting infinite_tracing.trace_observer.host.
      def enabled?
        distributed_tracing_enabled? && 
        span_events_enabled? && 
        trace_observer_configured?
      end

      # Distributed Tracing must be enabled for Infinite Tracing
      def distributed_tracing_enabled?
        NewRelic::Agent.config[:'distributed_tracing.enabled']
      end

      # Span Events must be enabled for Infinite Tracing
      def span_events_enabled?
        NewRelic::Agent.config[:'span_events.enabled']
      end

      # running locally is akin to communicating with the gRPC server with an 
      # unencrypted channel.  Generally, this is _not_ allowed by the agent
      # in normal use-cases.  The only known use-case for this is when 
      # streaming under TEST conditions.
      def local?
        test_framework?
      end

      # removes the scheme and port from a host entry.
      def without_scheme_or_port url
        url.gsub(%r{^https?://|:\d+$}, '')
      end

      def trace_observer_host
        without_scheme_or_port NewRelic::Agent.config[:'infinite_tracing.trace_observer.host']
      end

      # If the port is declared on the host entry, it overrides the port entry because otherwise
      # we'd need to figure out if user supplied the port or if the default source config set
      # the port.  To help with debugging configuration issues, we log whenever the port entry
      # is overriden by the presence of the port on the host entry.
      def port_from_host_entry
        port_str = NewRelic::Agent.config[:'infinite_tracing.trace_observer.host'].scan(%r{:(\d+)$}).flatten
        if port = (port_str[0] and port_str[0].to_i)
          NewRelic::Agent.logger.warn(":'infinite_tracing.trace_observer.port' is ignored if present because :'infinite_tracing.trace_observer.host' specifies the port")
          return port
        end
      end

      # This is the port the trace observer is listening on.  It can be supplied as a suffix
      # on the host entry or via the separate port entry.
      def trace_observer_port
        port_from_host_entry || NewRelic::Agent.config[:'infinite_tracing.trace_observer.port']
      end

      # The scheme is based on whether the Trace Observer is running locally or remotely. 
      # Remote unsecure (unencypted) streaming is disallowed!
      def trace_observer_scheme
        local? ? NewRelic::HTTP : NewRelic::HTTPS
      end

      # The uniform resource identifier of the Trace Observer host constructed from all the parts.
      def trace_observer_uri
        if trace_observer_configured?
          URI("#{trace_observer_scheme}://#{trace_observer_host_and_port}")
        else
          NewRelic::Agent.logger.error TRACE_OBSERVER_NOT_CONFIGURED_ERROR
          raise TRACE_OBSERVER_NOT_CONFIGURED_ERROR
        end
      end

      # returns host and port together expressed as +hostname:port+ string.
      def trace_observer_host_and_port
        "#{trace_observer_host}:#{trace_observer_port}"
      end

      # The maximum number of span events the Streaming Buffer can hold when buffering 
      # to stream across the gRPC channel.
      def span_events_queue_size
        NewRelic::Agent.config[:'span_events.queue_size']
      end

      # Returns TRUE if we're running in a test environment
      def test_framework?
        NewRelic::Agent.config[:framework] == :test
      end

      # Infinite Tracing is configured when a non
      def trace_observer_configured?
        trace_observer_host != NewRelic::EMPTY_STR
      end
    end
  end
end
