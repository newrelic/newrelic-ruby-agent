# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      class Tracer
        attr_accessor :name, :version

        def initialize(name, version)
          @name = name # || 'newrelic_rpm'
          @version = version # || NewRelic::VERSION::STRING
        end

        def start_root_span(name, attributes: nil, links: nil, start_timestamp: nil, kind: nil)
          binding.irb
          # start_transaction
        end

        def start_span(name, with_parent: nil, attributes: nil, links: nil, start_timestamp: nil, kind: nil)
          # start_segment maybe instead? But if you don't give it a parent, it just takes the current context and will create a new trace, right?
          # NewRelic::Agent::Tracer.start_transaction_or_segment
          binding.irb
          NewRelic::Agent::Tracer.start_segment(
            name: name,
            start_time: start_timestamp,
            parent: with_parent || NewRelic::Agent::Tracer.
          )
        end

        def in_span(name, attributes: nil, links: nil, start_timestamp: nil, kind: nil)
          # start_segment_or_transaction ?
          case kind
          when :internal
            binding.irb
            segment = NewRelic::Agent::Tracer.start_segment_or_transaction
          when :client
            # abstract this into a separate class
            begin
              # skipping the wrapped_request stuff from NR instrumentation for now
              segment = NewRelic::Agent::Tracer.start_external_request_segment(
                # otel tracers generally are named after the library
                # that's generating the trace
                library: self.name,
                uri: name,
                # does this change based on semconv?
                procedure: attributes['http.method'],
                start_time: start_timestamp
                # parent: ----
              )
              # do we try to capture segment errors?
              NewRelic::Agent::Tracer.capture_segment_error(segment) { yield }
            ensure
              segment&.finish
            end
          when :server
            binding.irb
          else
            binding.irb
          end
        end
      end
    end
  end
end
