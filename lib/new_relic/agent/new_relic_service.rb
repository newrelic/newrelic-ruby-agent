module NewRelic
  module Agent
    class NewRelicService
      attr_reader :agent_id

      def initialize(license_key, host, port=80)
        @license_key = license_key
        @collector = host
        @port = port
      end
      
      def connect(environment)
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

      def control
        NewRelic::Control.instance
      end

      private
      
      def invoke_remote(method, *args)
      end
      
      def get_redirect_host
      end

      def shutdown
      end
    end
  end
end
