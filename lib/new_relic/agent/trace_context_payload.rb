# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/distributed_trace_transport_types'

module NewRelic
  module Agent
    class TraceContextPayload
      VERSION = 0
      PARENT_TYPE = 0
      DELIMITER = "-".freeze
      SUPPORTABILITY_INVALID_PAYLOAD = "Supportability/TraceContext/Accept/Ignored/InvalidPayload".freeze

      TRUE_CHAR = '1'.freeze
      FALSE_CHAR = '0'.freeze

      PARENT_TYPES = %w(App Browser Mobile).map(&:freeze).freeze

      class << self
        def create version: VERSION,
                   parent_type: PARENT_TYPE,
                   parent_account_id: nil,
                   parent_app_id: nil,
                   id: nil,
                   transaction_id: nil,
                   sampled: nil,
                   priority: nil,
                   timestamp: now_ms

          new version, parent_type, parent_account_id, parent_app_id, id,
              transaction_id, sampled, priority, timestamp
        end

        def from_s payload_string
          attrs = payload_string.split(DELIMITER)

          payload = create \
            version: parse_int(attrs[0]),
            parent_type: parse_int(attrs[1]),
            parent_account_id: attrs[2],
            parent_app_id: attrs[3],
            id: parse_value(attrs[4]),
            transaction_id: parse_value(attrs[5]),
            sampled: parse_boolean(attrs[6]),
            priority: parse_float(attrs[7]),
            timestamp: parse_int(attrs[8])
          log_parse_error message: 'payload missing attributes' unless payload.valid?
          payload
        rescue => e
          log_invalid_payload error: e
        end

        private

        def now_ms
          (Time.now.to_f * 1000).round
        end

        def log_invalid_payload error: nil, message: nil
          NewRelic::Agent.increment_metric SUPPORTABILITY_INVALID_PAYLOAD
          if error
            NewRelic::Agent.logger.warn "Error parsing trace context payload", error
          elsif message
            NewRelic::Agent.logger.warn "Error parsing trace context payload: #{message}"
          end
        end

        def parse_value value
          return nil if value.nil? || value.empty?
          value
        end

        def parse_int value
          (parsed = parse_value value) && parsed.to_i
        end

        def parse_boolean value
          (parsed = parse_value value) && parsed == TRUE_CHAR
        end

        def parse_float value
          (parsed = parse_value value) && parsed.to_f
        end
      end

      attr_accessor :version,
                    :parent_type_id,
                    :parent_account_id,
                    :parent_app_id,
                    :id,
                    :transaction_id,
                    :sampled,
                    :priority,
                    :timestamp

      alias_method :sampled?, :sampled

      def initialize version, parent_type_id, parent_account_id, parent_app_id,
                     id, transaction_id, sampled, priority, timestamp
        @version = version
        @parent_type_id = parent_type_id
        @parent_account_id = parent_account_id
        @parent_app_id = parent_app_id
        @id = id
        @transaction_id = transaction_id
        @sampled = sampled
        @priority = priority
        @timestamp = timestamp
      end

      attr_reader :caller_transport_type

      def caller_transport_type= type
        @caller_transport_type = DistributedTraceTransportTypes.from type
      end

      def parent_type
        @parent_type_string ||= PARENT_TYPES[@parent_type_id]
      end

      def valid?
        !version.nil? \
          && !parent_type_id.nil? \
          && parent_account_id && !parent_account_id.empty? \
          && parent_app_id && !parent_app_id.empty? \
          && !timestamp.nil?
      rescue
        false
      end

      EMPTY = "".freeze

      def to_s
        result = version.to_s
        result << DELIMITER << parent_type_id.to_s
        result << DELIMITER << parent_account_id
        result << DELIMITER << parent_app_id
        result << DELIMITER << (id || EMPTY)
        result << DELIMITER << (transaction_id || EMPTY)
        result << DELIMITER << (sampled ? TRUE_CHAR : FALSE_CHAR)
        result << DELIMITER << priority.to_s
        result << DELIMITER << timestamp.to_s
        result
      end
    end
  end
end
