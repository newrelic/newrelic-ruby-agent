# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class CrossAppPayload
      attr_reader :id, :transaction, :referring_guid, :referring_trip_id, :referring_path_hash

      def initialize(id, transaction, transaction_info)
        @id                  = id
        @transaction         = transaction

        transaction_info ||= []
        @referring_guid      = transaction_info[0]
        # unused_flag        = transaction_info[1]
        @referring_trip_id   = string_or_false_for(transaction_info[2])
        @referring_path_hash = string_or_false_for(transaction_info[3])
      end

      def as_json_array(content_length)
        queue_time_in_seconds = [transaction.queue_time.to_f, 0.0].max
        start_time_in_seconds = [transaction.start_time.to_f, 0.0].max
        app_time_in_seconds   = Time.now.to_f - start_time_in_seconds

        [
          NewRelic::Agent.config[:cross_process_id],
          transaction.best_name,
          queue_time_in_seconds.to_f,
          app_time_in_seconds.to_f,
          content_length,
          transaction.guid,
          false
        ]
      end

      private

      def string_or_false_for(value)
        value.is_a?(String) && value
      end
    end
  end
end
