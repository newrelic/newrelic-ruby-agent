# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/distributed_trace_payload'

module NewRelic
  module Agent
    class TraceContext
      VERSION = 0x0
      TRACEPARENT = 'traceparent'.freeze
      TRACESTATE  = 'tracestate'.freeze

      TRACEPARENT_RACK = 'HTTP_TRACEPARENT'.freeze
      TRACESTATE_RACK  = 'HTTP_TRACESTATE'.freeze

      FORMAT_HTTP = 0
      FORMAT_RACK = 1

      TRACEPARENT_REGEX = /\A(?<version>\d{2})-(?<trace_id>[a-f\d]{32})-(?<parent_id>[a-f\d]{16})-(?<trace_flags>\d{2})\z/.freeze

      MAX_TRACE_STATE_SIZE = 512 # bytes

      class << self
        def insert format: FORMAT_HTTP,
                   carrier: nil,
                   parent_id: nil,
                   trace_id: nil,
                   trace_flags: nil,
                   trace_state: nil

          traceparent_header = traceparent_header_for_format format
          carrier[traceparent_header] = format_trace_parent \
            trace_id: trace_id,
            parent_id: parent_id,
            trace_flags: trace_flags

          tracestate_header = tracestate_header_for_format format
          carrier[tracestate_header] = trace_state if trace_state
        end

        def parse format: FORMAT_HTTP,
                  carrier: nil,
                  tracestate_entry_key: nil

          return unless traceparent = extract_traceparent(format, carrier)

          if data = extract_tracestate(format, carrier, tracestate_entry_key)
            data.traceparent = traceparent
            data
          end
        end

        private

        TRACEPARENT_FORMAT_STRING = "%02x-%s-%s-%02x".freeze

        def format_trace_parent trace_id: nil,
                                parent_id: nil,
                                trace_flags: nil
          sprintf TRACEPARENT_FORMAT_STRING,
                  VERSION,
                  trace_id,
                  parent_id,
                  trace_flags
        end

        def extract_traceparent format, carrier
          header_name = traceparent_header_for_format format
          header = carrier[header_name]
          if matchdata = header.match(TRACEPARENT_REGEX)
            TRACEPARENT_REGEX.named_captures.inject({}) do |hash, (name, (index))|
              hash[name] = matchdata[index]
              hash
            end
          end
        end

        def traceparent_header_for_format format
          if format == FORMAT_RACK
            TRACEPARENT_RACK
          else
            TRACEPARENT
          end
        end

        def tracestate_header_for_format format
          if format == FORMAT_RACK
            TRACESTATE_RACK
          else
            TRACESTATE
          end
        end

        COMMA = ','.freeze

        def extract_tracestate format, carrier, tracestate_entry_key
          header_name = tracestate_header_for_format format
          header = carrier[header_name]
          payload = nil

          tracestate = header.split(COMMA)
          tracestate_entry_prefix = "#{tracestate_entry_key}="
          tracestate.reject! do |entry|
            if entry.start_with? tracestate_entry_prefix
              payload = entry.slice! tracestate_entry_key.size + 1,
                                     entry.size
              !!payload
            end
          end

          Data.create trace_state_payload: payload ? decode_payload(payload) : nil,
                      other_trace_state_entries: tracestate
        end

        SUPPORTABILITY_TRACE_CONTEXT_ACCEPT_IGNORED_PARSE_EXCEPTION = "Supportability/TraceContext/AcceptPayload/ParseException".freeze

        def decode_payload payload
          DistributedTracePayload.from_http_safe(payload)
        rescue => e
          NewRelic::Agent.increment_metric SUPPORTABILITY_TRACE_CONTEXT_ACCEPT_IGNORED_PARSE_EXCEPTION
          NewRelic::Agent.logger.warn "Error parsing trace context payload", e
          nil
        end
      end

      class Data
        class << self
          def create traceparent: nil,
                     trace_state_payload: nil,
                     other_trace_state_entries: nil
            new traceparent, trace_state_payload, other_trace_state_entries
          end
        end

        def initialize traceparent, trace_state_payload, other_trace_state_entries
          @traceparent = traceparent
          @other_trace_state_entries = other_trace_state_entries
          @trace_state_payload = trace_state_payload
        end

        attr_accessor :traceparent, :trace_state_payload

        def tracestate
          @tracestate ||= @other_trace_state_entries.join(",")
          @other_trace_state_entries = nil
          @tracestate
        end

        def set_entry_size entry_size
          # this method trims the trace_state array being stored in memory so
          # that, when joined with a comma delimiter and prepended with a
          # trace state entry of the specified entry_size, the resulting string
          # will be less than or equal to MAX_TRACE_STATE_SIZE
          # If this method is called _after_ the array of trace state entries
          # has been converted to a string, it has no effect.  
          # This method is destructive.  After calling `set_entry_size 100`,
          # calling with a number less than 100 will have no effect.
          bytes_to_remove = array_size - (MAX_TRACE_STATE_SIZE - entry_size)
          while bytes_to_remove > 0
            bytes_to_remove -= @other_trace_state_entries.pop.bytesize
          end
        end

        private

        def array_size
          return 0 unless @other_trace_state_entries
          @other_trace_state_entries.inject(0) do |size, char|
            size += char.bytesize + 1
            size
          end
        end
      end

      module AccountHelpers
        extend self
        def tracestate_entry_key
          @tracestate_entry_key ||= if Agent.config[:trusted_account_key]
            "t#{Agent.config[:trusted_account_key].to_i.to_s(36)}@nr".freeze
          elsif Agent.config[:account_id]
            "t#{Agent.config[:account_id].to_i.to_s(36)}@nr".freeze
          end
        end
      end
    end
  end
end
