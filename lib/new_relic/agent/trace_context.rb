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

      TRACE_PARENT_REGEX = /\A(?<version>[a-f\d]{2})-(?<trace_id>[a-f\d]{32})-(?<parent_id>[a-f\d]{16})-(?<trace_flags>\d{2})(?<undefined_fields>-[a-zA-Z\d-]*)?\z/.freeze

      COMMA = ','.freeze
      EMPTY_STRING = ''.freeze
      TRACE_ID_KEY = 'trace_id'.freeze
      PARENT_ID_KEY = 'parent_id'.freeze
      VERSION_KEY = 'version'.freeze
      UNDEFINED_FIELDS_KEY = 'undefined_fields'.freeze
      INVALID_TRACE_ID = ('0' * 32).freeze
      INVALID_PARENT_ID = ('0' * 16).freeze
      INVALID_VERSION = 'ff'.freeze

      MAX_TRACE_STATE_SIZE = 512 # bytes
      MAX_TRACE_STATE_ENTRY_SIZE = 128 # bytes

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
          return unless trace_parent_valid? trace_parent

          if data = extract_tracestate(format, carrier, trace_state_entry_key)
            data.trace_parent = trace_parent
            data
          end
        end

        def create_trace_state_entry entry_key, payload
          "#{entry_key}=#{payload}"
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

        def trace_parent_valid? trace_parent
          return false if trace_parent[TRACE_ID_KEY] == INVALID_TRACE_ID
          return false if trace_parent[PARENT_ID_KEY] == INVALID_PARENT_ID
          return false if trace_parent[VERSION_KEY] == INVALID_VERSION
          return false if trace_parent[VERSION_KEY].to_i(16) == VERSION && !trace_parent[UNDEFINED_FIELDS_KEY].nil?

          true
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

        def trace_state trace_state_entry
          new_entry_size = trace_state_entry.size
          bytes_available_for_other_entries = MAX_TRACE_STATE_SIZE - new_entry_size - COMMA.size

          @trace_state ||= join_other_trace_state bytes_available_for_other_entries
          @other_trace_state_entries = nil

          trace_state_entry << COMMA << @trace_state unless @trace_state.empty?
          trace_state_entry
        end

        def trace_id
          @trace_parent[TRACE_ID_KEY]
        end

        private

        def join_other_trace_state max_size
          return @trace_state || EMPTY_STRING if @other_trace_state_entries.nil?
          return @other_trace_state_entries.join(COMMA) if joined_size(@other_trace_state_entries) < max_size

          other_trace_state = ''

          used_size = 0
          entry_index = 0

          @other_trace_state_entries.each do |entry|
            entry_size = entry.size
            break if used_size + entry_size >= max_size
            next if entry_size > MAX_TRACE_STATE_ENTRY_SIZE

            if entry_index > 0
              other_trace_state << COMMA
              used_size += 1
            end
            other_trace_state << entry
            used_size += entry_size
            entry_index += 1
          end

          other_trace_state
        end

        def joined_size array
          # The joined array size is the sum of the size of each string in
          # the array, plus one byte for each comma used to delimit the resulting
          # string (which is array.size - 1)
          size = array.inject(0) do |size, entry|
            size += entry.size
            size
          end
          size + array.length - 1
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
