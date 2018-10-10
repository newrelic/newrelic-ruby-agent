# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'json'

module NewRelic
  module Agent
    class CrossAppPayload
      attr_reader :transaction, :referring_guid, :referring_trip_id, :referring_path_hash

      def initialize(transaction, transaction_info)
        @transaction         = transaction

        transaction_info ||= []
        @referring_guid      = transaction_info[0]
        # unused_flag        = transaction_info[1]
        @referring_trip_id   = string_or_false_for(transaction_info[2])
        @referring_path_hash = string_or_false_for(transaction_info[3])
      end

      def build_payload(content_length)
        queue_time_in_seconds = [transaction.queue_time.to_f, 0.0].max
        start_time_in_seconds = [transaction.start_time.to_f, 0.0].max
        app_time_in_seconds   = Time.now.to_f - start_time_in_seconds

        raw_payload = [
          NewRelic::Agent.config[:cross_process_id],
          transaction.best_name,
          queue_time_in_seconds.to_f,
          app_time_in_seconds.to_f,
          content_length,
          transaction.guid
        ]

        ::JSON.dump(raw_payload)
      end

      private

      def string_or_false_for(value)
        value.is_a?(String) && value
      end
    end
  end
end
