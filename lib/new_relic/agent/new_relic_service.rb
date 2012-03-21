module NewRelic
  module Agent
    class NewRelicService
      def initialize(agent, license_key, host)
      end

      ### API
      
      def connect
      end
      
      def disconnect
      end
      
      def send_metric_data
      end

      def send_sql_trace_data
      end

      def send_transaction_trace_data
      end

      def send_error_data
      end

      ### refactoring cruft

      private
      
      def invoke_remote
        # called by e'rybody
      end

      def get_redirect_host
        # called by connect
      end

      def shutdown
        # called by disconnect
      end
    end
  end
end
