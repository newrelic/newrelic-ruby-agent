module NewRelic
  module Agent
    class TransactionInfo
      
      attr_accessor :token, :capture_deep_tt, :transaction_name
      attr_reader :start_time
      
      def initialize
        @guid = ""
        @transaction_name = "(unknown)"
        @start_time = Time.now
      end
      
      def force_persist_sample?(sample)
        token && sample.duration > NewRelic::Control.instance.apdex_t
      end
      
      def include_guid?
        token && duration > NewRelic::Control.instance.apdex_t
      end
      
      def guid
        @guid
      end
      
      def guid=(value)
        @guid = value
      end
      
      def duration
        Time.now - start_time
      end
      
      def self.get()
        Thread.current[:newrelic_transaction_info] ||= TransactionInfo.new
      end
      
      def self.set(instance)
        Thread.current[:newrelic_transaction_info] = instance
      end
      
      def self.clear
        Thread.current[:newrelic_transaction_info] = nil
      end
      
    end
  end
end

