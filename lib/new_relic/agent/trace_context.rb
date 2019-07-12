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
          tenant_id = nil
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

          Data.create tenant_id: tenant_id,
                      tracestate_entry: payload ? decode_payload(payload) : nil,
                      tracestate_array: tracestate
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
                     tenant_id: nil,
                     tracestate_entry: nil,
                     tracestate_array: nil
            new traceparent, tenant_id, tracestate_entry, tracestate_array
          end
        end

        def initialize traceparent, tenant_id, tracestate_entry, tracestate_array
          @traceparent = traceparent
          @tracestate_array = tracestate_array
          @tracestate_entry = tracestate_entry
          @tenant_id = tenant_id
        end

        attr_accessor :traceparent, :tracestate_entry, :tenant_id

        def tracestate
          @tracestate ||= @tracestate_array.join(",")
          @tracestate_array = nil
          @tracestate
        end
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
