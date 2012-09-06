require 'erb'

module NewRelic
  module Agent
    class TransactionInfo

      attr_accessor :token, :capture_deep_tt, :transaction_name
      attr_reader :start_time

      def initialize
        @guid = ""
        @transaction_name = "(unknown)"
        @start_time = Time.now
        @ignore_end_user = false
      end

      def force_persist_sample?(sample)
        token && sample.duration > Agent.config[:apdex_t]
      end

      def include_guid?
        token && duration > Agent.config[:apdex_t]
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
      
      def ignore_end_user?
        @ignore_end_user
      end
      
      def ignore_end_user=(value)
        @ignore_end_user = value
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

      # clears any existing transaction info object and initializes a new one.
      # This starts the timer for the transaction.
      def self.reset(request=nil)
        clear
        instance = get
        instance.token = get_token(request)
      end

      def self.get_token(request)
        return nil unless request
        
        agent_flag = request.cookies['NRAGENT']
        if agent_flag and agent_flag.instance_of? String 
          s = agent_flag.split("=")
          if s.length == 2
            if s[0] == "tk" && s[1]
              ERB::Util.h(sanitize_token(s[1]))
            end
          end
        else
          nil
        end
      end

      # Run through a collection of unsafe characters ( in the context of the token ) 
      # and set the token to an empty string if any of them are found in the token so that
      # potential XSS attacks via the token are avoided
      def self.sanitize_token(token)

        if ( /[<>'"]/ =~ token )
          token.replace("")
        end
        token
      end
    end
  end
end

