# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class TraceContext
      VERSION     = 0x0
      TRACEPARENT = 'traceparent'.freeze
      TRACESTATE  = 'tracestate'.freeze

      TRACEPARENT_RACK = 'HTTP_TRACEPARENT'.freeze

      FORMAT_TEXT_MAP = 0
      FORMAT_RACK     = 1

      TRACEPARENT_REGEX = /\A(?<version>\d{2})-(?<trace_id>[a-f\d]{32})-(?<parent_id>[a-f\d]{16})-(?<trace_flags>\d{2})\z/

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



        # return a TraceContext::Data
        def parse format: FORMAT_TEXT_MAP,
                  carrier: nil
          traceparent = extract_traceparent format, carrier
          tracestate_entry = nil
          tracestate = nil
          Data.new traceparent, tracestate_entry, tracestate
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

        def extract_traceparent format, carrier
          header_name = traceparent_header_for_format format
          header = carrier[header_name]
          if matchdata = header.match(TRACEPARENT_REGEX)
            matchdata.named_captures
          end
        end

        def traceparent_header_for_format format
          if format == FORMAT_RACK
            TRACEPARENT_RACK
          else
            TRACEPARENT
          end
        end
      end
    end

    class Data
      def initialize traceparent, tracestate_entry, tracestate
        @traceparent = traceparent
        @tracestate_entry = tracestate_entry
        @tracestate = tracestate
      end
      # hash trace_id,parent_id,trace_flags,version
      def traceparent
        @traceparent
      end

      # our tracestate entry, decoded, if there was one
      def tracestate_entry
      end

      # a pruned and ready to append to, string representation of tracestate
      def tracestate
      end
    end
  end
end
