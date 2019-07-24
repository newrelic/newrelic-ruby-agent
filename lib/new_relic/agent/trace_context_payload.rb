# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class TraceContextPayload
      VERSION = 0
      PARENT_TYPE = 0
      DELIMITER = "-".freeze
      SUPPORTABILITY_TRACE_CONTEXT_ACCEPT_IGNORED_PARSE_EXCEPTION = "Supportability/TraceContext/AcceptPayload/ParseException".freeze

      TRUE_CHAR = '1'.freeze
      FALSE_CHAR = '0'.freeze

      class << self
        def from_s payload_string
          attrs = payload_string.split(DELIMITER)

          if attrs.size < 9
            log_parse_error message: "attributes missing from payload"
            return
          end

          payload = new
          payload.version = attrs[0].to_i
          payload.parent_type = attrs[1].to_i
          payload.parent_account_id = attrs[2]
          payload.parent_app_id = attrs[3]
          payload.id = attrs[4]
          payload.transaction_id = attrs[5].empty? ? nil : attrs[5]
          payload.sampled = attrs[6].empty? ? nil : (attrs[6] == TRUE_CHAR)
          payload.priority = (attrs[7].empty? ? nil : attrs[7].to_f)
          payload.timestamp = attrs[8].to_i
          payload
        rescue => e
          log_parse_error error: e
        end

        private

        def log_parse_error error: nil, message: nil
          NewRelic::Agent.increment_metric SUPPORTABILITY_TRACE_CONTEXT_ACCEPT_IGNORED_PARSE_EXCEPTION
          if error
            NewRelic::Agent.logger.warn "Error parsing trace context payload", error
          elsif message
            NewRelic::Agent.logger.warn "Error parsing trace context payload: #{message}"
          end
        end
      end

      attr_accessor :version,
                    :parent_type,
                    :parent_account_id,
                    :parent_app_id,
                    :id,
                    :transaction_id,
                    :sampled,
                    :priority,
                    :timestamp

      alias_method :sampled?, :sampled

      def initialize
        @version = VERSION
        @parent_type = PARENT_TYPE
        @timestamp = (Time.now.to_f * 1000).round
      end

      EMPTY = "".freeze

      def to_s
        result = version.to_s
        result << DELIMITER << parent_type.to_s
        result << DELIMITER << parent_account_id
        result << DELIMITER << parent_app_id
        result << DELIMITER << (id || EMPTY)
        result << DELIMITER << transaction_id
        result << DELIMITER << (sampled ? TRUE_CHAR : FALSE_CHAR)
        result << DELIMITER << priority.to_s
        result << DELIMITER << timestamp.to_s
        result
      end
    end
  end
end
