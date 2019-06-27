# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class TraceContext
      VERSION     = 0x0
      TRACEPARENT = 'traceparent'.freeze
      TRACESTATE  = 'tracestate'.freeze

      class << self
        def insert carrier: nil,
                   parent_id: nil,
                   trace_id: nil,
                   trace_flags: nil,
                   trace_state: nil

          carrier[TRACEPARENT] = format_trace_parent \
            trace_id: trace_id,
            parent_id: parent_id,
            trace_flags: trace_flags

          carrier[TRACESTATE] = trace_state if trace_state
        end

        private

        def format_trace_parent trace_id: nil,
                                parent_id: nil,
                                trace_flags: nil
          sprintf "%02x-%s-%s-%02x",
                  VERSION,
                  trace_id,
                  parent_id,
                  trace_flags
        end

      end
    end
  end
end
