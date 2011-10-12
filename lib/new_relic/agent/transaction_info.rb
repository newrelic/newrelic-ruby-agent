module NewRelic
  module Agent
    class TransactionInfo
      
      attr_accessor :force_persist, :capture_if_greater_than_apdex_t, :capture_deep_tt, :transaction_name
      attr_reader :start_time
      
      def initialize
        @guid = ""
        @transaction_name = "(unknown)"
        @start_time = Time.now
      end
      
      def force_persist_sample?(sample)
        self.force_persist=(capture_if_greater_than_apdex_t && sample.duration > NewRelic::Control.instance.apdex_t)
      end
      
      def guid
        if force_persist
          @guid
        else
          ""
        end
      end
      
      def guid=(value)
        @guid = value
      end
      
      def TransactionInfo.get()
        Thread.current[:transaction_info] || (Thread.current[:transaction_info] = TransactionInfo.new)
      end
      
      def TransactionInfo.set(instance)
        Thread.current[:transaction_info] = instance
      end
      
      def TransactionInfo.clear
        Thread.current[:transaction_info] = nil
      end
      
    end
  end
end

