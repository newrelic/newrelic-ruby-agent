# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class TransactionTimings

      def initialize(queue_time_in_seconds, state)
        @now = Time.now.to_f
        if state.nil?
          @start_time_in_seconds = 0.0
        else
          @start_time_in_seconds = state.transaction_start_time.to_f
          if !state.transaction.nil?
            @transaction_name = state.transaction.name
          end
        end

        @queue_time_in_seconds = clamp_to_positive(queue_time_in_seconds.to_f)
      end

      attr_reader :transaction_name,
        :start_time_in_seconds, :queue_time_in_seconds

      def start_time_as_time
        Time.at(@start_time_in_seconds)
      end

      def start_time_in_millis
        convert_to_milliseconds(@start_time_in_seconds)
      end

      def queue_time_in_millis
        convert_to_milliseconds(queue_time_in_seconds)
      end

      def app_time_in_millis
        convert_to_milliseconds(app_time_in_seconds)
      end

      def app_time_in_seconds
        @now - @start_time_in_seconds
      end

      # Helpers

      def convert_to_milliseconds(value_in_seconds)
        clamp_to_positive((value_in_seconds.to_f * 1000.0).round)
      end

      def clamp_to_positive(value)
        return 0.0 if value < 0.0
        value
      end

    end
  end
end
