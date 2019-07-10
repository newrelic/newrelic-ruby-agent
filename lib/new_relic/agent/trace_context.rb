# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/distributed_trace_payload'

module NewRelic
  module Agent
    class TraceContext
      VERSION = 0x0

      TRACEPARENT_REGEX = /\A(?<version>\d{2})-(?<trace_id>[a-f\d]{32})-(?<parent_id>[a-f\d]{16})-(?<trace_flags>\d{2})\z/.freeze

      module RackFormat
        TRACEPARENT = 'HTTP_TRACEPARENT'.freeze
        TRACESTATE = 'HTTP_TRACESTATE'.freeze
      end

      module HttpFormat
        TRACEPARENT = 'traceparent'.freeze
        TRACESTATE  = 'tracestate'.freeze
      end

      class << self
        def insert format: RackFormat,
                   carrier: nil,
                   parent_id: nil,
                   trace_id: nil,
                   trace_flags: nil,
                   trace_state: nil

          carrier[format::TRACEPARENT] = format_trace_parent \
            trace_id: trace_id,
            parent_id: parent_id,
            trace_flags: trace_flags

          carrier[format::TRACESTATE] = trace_state if trace_state
        end

        def parse format: HttpFormat,
                  carrier: nil,
                  tracestate_entry_key: nil

          traceparent = extract_traceparent format, carrier
          return if traceparent.nil?

          tenant_id, tracestate_entry, tracestate = extract_tracestate format, carrier, tracestate_entry_key

          Data.new traceparent, tenant_id, tracestate_entry, tracestate
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
          header_name = format::TRACEPARENT
          header = carrier[header_name]
          if matchdata = header.match(TRACEPARENT_REGEX)
            matchdata.named_captures
          end
        end

        COMMA = ','.freeze
        EMPTY_STRING = ''.freeze

        def extract_tracestate format, carrier, tracestate_entry_key
          header_name = format::TRACESTATE
          header = carrier[header_name]
          tenant_id = nil
          payload = nil

          tracestate = header.split(COMMA)
          tracestate_entry_prefix = "#{tracestate_entry_key}="
          tracestate.reject! do |entry|
            if entry.start_with? tracestate_entry_prefix
              payload = entry.gsub!(tracestate_entry_prefix, EMPTY_STRING)
              !!payload
            end
          end

          [
            tenant_id,
            payload ? DistributedTracePayload.from_http_safe(payload) : nil,
            tracestate
          ]
        end
      end
      class Data
        def initialize traceparent, tenant_id, tracestate_entry, tracestate
          @traceparent = traceparent
          @tracestate_entry = tracestate_entry
          @tracestate = tracestate
          @tenant_id = tenant_id
        end

        attr_reader :traceparent, :tracestate_entry, :tracestate, :tenant_id
      end
      # is there a better place for this?
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
