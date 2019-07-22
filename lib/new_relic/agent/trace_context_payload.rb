# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class TraceContextPayload
      VERSION = 0
      PARENT_TYPE = 0
      DELIMITER = "-".freeze

      class << self
        def from_s payload_string
          attrs = payload_string.split(DELIMITER)
          return unless attrs.size == 9

          payload = new
          payload.version = attrs[0]
          payload.parent_type = attrs[1]
          payload.parent_account_id = attrs[2]
          payload.parent_app_id = attrs[3]
          payload.id = attrs[4]
          payload.transaction_id = attrs[5]
          payload.sampled = (attrs[6] == "1" ? true : false)
          payload.priority = attrs[7].to_f
          payload.timestamp = attrs[8].to_f
          payload
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

      def to_s
        result = version.to_s
        result << DELIMITER << parent_type.to_s
        result << DELIMITER << parent_account_id
        result << DELIMITER << parent_app_id
        result << DELIMITER << id
        result << DELIMITER << transaction_id
        result << DELIMITER << (sampled ? 1 : 0).to_s
        result << DELIMITER << priority.to_s
        result << DELIMITER << timestamp.to_s
        result
      end
    end
  end
end
