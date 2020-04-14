# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent
  module InfiniteTracing
    module Config
      extend self

      def should_load?
        test_framework? || trace_obsever_configured?
      end

      def enabled?
        trace_observer_configured?
      end

      def local?
        test_framework? || trace_observer_port == 80
      end

      def without_scheme_or_port url
        url.gsub(%r{^https?://|:\d+$}, '')
      end

      def trace_observer_host
        without_scheme_or_port NewRelic::Agent.config[:'infinite_tracing.trace_observer.host']
      end

      def port_from_host_entry
        port_str = NewRelic::Agent.config[:'infinite_tracing.trace_observer.host'].scan(%r{:(\d+)$}).flatten
        if port = (port_str[0] and port_str[0].to_i)
          ::NewRelic::Agent.logger.warn(":'infinite_tracing.trace_observer.port' is ignored if present because :'infinite_tracing.trace_observer.host' specifies the port")
          return port
        end
      end

      def trace_observer_port
        port_from_host_entry || NewRelic::Agent.config[:'infinite_tracing.trace_observer.port']
      end

      def trace_observer_scheme
        local? ? NewRelic::HTTP : NewRelic::HTTPS
      end

      def trace_observer_uri
        URI("#{trace_observer_scheme}://#{trace_observer_host}:#{trace_observer_port}")
      end

      def span_events_queue_size
        NewRelic::Agent.config[:'span_events.queue_size']
      end

      def test_framework?
        NewRelic::Agent.config[:framework] == :test
      end

      def trace_observer_configured?
        trace_observer_host != NewRelic::EMPTY_STR
      end
    end
  end
end
