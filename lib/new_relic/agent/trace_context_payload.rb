# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class TraceContextPayload
      VERSION = 0
      PARENT_TYPE = 0

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

      def to_a
        [
          version,
          parent_type,
          parent_account_id,
          parent_app_id,
          id,
          transaction_id,
          sampled ? 1 : 0,
          priority,
          timestamp
        ]
      end

      DELIMITER = "-".freeze

      def to_s
        to_a.join(DELIMITER)
      end
    end
  end
end