# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/distributed_trace_payload'

module NewRelic
  module Agent
    class TraceContext
      VERSION = 0x0
      TRACE_PARENT = 'traceparent'.freeze
      TRACE_STATE  = 'tracestate'.freeze

      TRACE_PARENT_RACK = 'HTTP_TRACEPARENT'.freeze
      TRACE_STATE_RACK  = 'HTTP_TRACESTATE'.freeze

      FORMAT_HTTP = 0
      FORMAT_RACK = 1

      TRACE_PARENT_REGEX = /\A(?<version>\d{2})-(?<trace_id>[a-f\d]{32})-(?<parent_id>[a-f\d]{16})-(?<trace_flags>\d{2})\z/.freeze

      COMMA = ','.freeze
      TRACE_ID_KEY = 'trace_id'.freeze

      MAX_TRACE_STATE_SIZE = 512 # bytes

      class << self
        def insert format: FORMAT_HTTP,
                   carrier: nil,
                   parent_id: nil,
                   trace_id: nil,
                   trace_flags: nil,
                   trace_state: nil

          trace_parent_header = trace_parent_header_for_format format
          carrier[trace_parent_header] = format_trace_parent \
            trace_id: trace_id,
            parent_id: parent_id,
            trace_flags: trace_flags

          trace_state_header = trace_state_header_for_format format
          carrier[trace_state_header] = trace_state if trace_state
        end

        def parse format: FORMAT_HTTP,
                  carrier: nil,
                  trace_state_entry_key: nil

          return unless trace_parent = extract_traceparent(format, carrier)

          if data = extract_tracestate(format, carrier, trace_state_entry_key)
            data.trace_parent = trace_parent
            data
          end
        end

        private

        TRACE_PARENT_FORMAT_STRING = "%02x-%s-%s-%02x".freeze

        def format_trace_parent trace_id: nil,
                                parent_id: nil,
                                trace_flags: nil
          sprintf TRACE_PARENT_FORMAT_STRING,
                  VERSION,
                  trace_id,
                  parent_id,
                  trace_flags
        end

        def extract_traceparent format, carrier
          header_name = trace_parent_header_for_format format
          header = carrier[header_name]
          if matchdata = header.match(TRACE_PARENT_REGEX)
            TRACE_PARENT_REGEX.named_captures.inject({}) do |hash, (name, (index))|
              hash[name] = matchdata[index]
              hash
            end
          end
        end

        def trace_parent_header_for_format format
          if format == FORMAT_RACK
            TRACE_PARENT_RACK
          else
            TRACE_PARENT
          end
        end

        def trace_state_header_for_format format
          if format == FORMAT_RACK
            TRACE_STATE_RACK
          else
            TRACE_STATE
          end
        end

        def extract_tracestate format, carrier, trace_state_entry_key
          header_name = trace_state_header_for_format format
          header = carrier[header_name]
          return Data.new nil, nil, [] if header.nil? || header.empty?

          payload = nil

          trace_state = header.split(COMMA)
          trace_state_entry_prefix = "#{trace_state_entry_key}="
          trace_state.reject! do |entry|
            if entry.start_with? trace_state_entry_prefix
              payload = entry.slice! trace_state_entry_key.size + 1,
                                     entry.size
              !!payload
            end
          end

          Data.create trace_state_payload: payload ? decode_payload(payload) : nil,
                      other_trace_state_entries: trace_state
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
        TRACE_ID_KEY = 'trace_id'.freeze

        class << self
          def create trace_parent: nil,
                     trace_state_payload: nil,
                     other_trace_state_entries: nil
            new trace_parent, trace_state_payload, other_trace_state_entries
          end
        end

        def initialize trace_parent, trace_state_payload, other_trace_state_entries
          @trace_parent = trace_parent
          @other_trace_state_entries = other_trace_state_entries
          @trace_state_payload = trace_state_payload
        end

        attr_accessor :trace_parent, :trace_state_payload

        def trace_state
          @trace_state ||= @other_trace_state_entries.join(COMMA)
          @other_trace_state_entries = nil
          @trace_state
        end

        def trace_id
          @trace_parent[TRACE_ID_KEY]
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
        def trace_state_entry_key
          @trace_state_entry_key ||= if Agent.config[:trusted_account_key]
            "t#{Agent.config[:trusted_account_key].to_i.to_s(36)}@nr".freeze
          elsif Agent.config[:account_id]
            "t#{Agent.config[:account_id].to_i.to_s(36)}@nr".freeze
          end
        end
      end
    end
  end
end
