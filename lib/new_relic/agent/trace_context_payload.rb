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

      PARENT_TYPES = [
        'App'.freeze,     # type 0
        'Browser'.freeze, # type 1
        'Mobile'.freeze   # type 2
      ].freeze

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

          if attrs.size < 9
            log_invalid_payload message: "attributes missing from payload"
            return
          end

          create \
            version: attrs[0].to_i,
            parent_type: attrs[1].to_i,
            parent_account_id: attrs[2],
            parent_app_id: attrs[3],
            id: attrs[4],
            transaction_id: nil_or_empty?(attrs[5]) ? nil : attrs[5],
            sampled: nil_or_empty?(attrs[6]) ? nil : (attrs[6] == TRUE_CHAR),
            priority: nil_or_empty?(attrs[7]) ? nil : attrs[7].to_f,
            timestamp: nil_or_empty?(attrs[8]) ? nil : attrs[8].to_i
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

        def nil_or_empty? value
          value.nil? || value.empty?
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
          && id && !id.empty? \
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
        result << DELIMITER << (id || EMPTY) # we allow an empty span id?
        result << DELIMITER << transaction_id
        result << DELIMITER << (sampled ? TRUE_CHAR : FALSE_CHAR)
        result << DELIMITER << priority.to_s
        result << DELIMITER << timestamp.to_s
        result
      end
    end
  end
end
