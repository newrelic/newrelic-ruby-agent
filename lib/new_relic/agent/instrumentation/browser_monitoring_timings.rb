module NewRelic
  module Agent
    module Instrumentation
      class BrowserMonitoringTimings

        def initialize(queue_time_in_seconds, transaction)
          if transaction.nil?
            @start_time_in_seconds = 0.0
          else
            @transaction_name = transaction.transaction_name
            @start_time_in_seconds = transaction.start_time
          end

          @queue_time_in_seconds = queue_time_in_seconds
        end

        attr_reader :transaction_name

        def start_time_in_millis
          convert_to_milliseconds(@start_time_in_seconds)
        end

        def queue_time_in_millis
          convert_to_milliseconds(@queue_time_in_seconds)
        end

        def app_time_in_millis
          convert_to_milliseconds(Time.now - @start_time_in_seconds)
        end

        private

        def convert_to_milliseconds(value)
          value = (value.to_f * 1000.0).round
          return 0.0 if value < 0
          value
        end
      end
    end
  end
end
