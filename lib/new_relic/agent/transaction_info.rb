# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class TransactionInfo

      def token
        TransactionState.get.request_token
      end

      def transaction
        TransactionState.get.request_transaction
      end

      def start_time
        TransactionState.get.request_start
      end

      def force_persist_sample?(sample)
        token && sample.duration > Agent.config[:apdex_t]
      end

      def include_guid?
        token && duration > Agent.config[:apdex_t]
      end

      def guid
        TransactionState.get.request_guid
      end

      def guid=(value)
        TransactionState.get.request_guid = value
      end

      def duration
        Time.now - self.start_time
      end

      def ignore_end_user?
        TransactionState.get.request_ignore_enduser
      end

      def ignore_end_user=(value)
        TransactionState.get.request_ignore_enduser = value
      end

      def apdex_t
        (Agent.config[:web_transactions_apdex] &&
         Agent.config[:web_transactions_apdex][self.transaction.name]) ||
          Agent.config[:apdex_t]
      end

      def transaction_trace_threshold
        key = :'transaction_tracer.transaction_threshold'
        if Agent.config.source(key).class == Configuration::DefaultSource
          apdex_t * 4
        else
          Agent.config[key]
        end
      end

      def self.get()
        TransactionInfo.new
      end

      # clears any existing transaction info object and initializes a new one.
      # This starts the timer for the transaction.
      def self.reset(request=nil)
        TransactionState.get.reset_request(request)
      end
    end
  end
end
