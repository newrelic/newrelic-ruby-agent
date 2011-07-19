require 'new_relic/agent'
require 'new_relic/control'
module NewRelic
  module Agent

    class SqlSampler

      # Module defining methods stubbed out when the agent is disabled
      module Shim #:nodoc:
        def notice_scope_empty(*args); end
      end

      attr_reader :disabled

      def initialize

        config = NewRelic::Control.instance
        sampler_config = config.fetch('transaction_tracer', {})
        @explain_threshold = sampler_config.fetch('explain_threshold', 0.5).to_f

        # This lock is used to synchronize access to the @last_sample
        # and related variables. It can become necessary on JRuby or
        # any 'honest-to-god'-multithreaded system
        @samples_lock = Mutex.new
      end

      # Enable the sql sampler - this also registers it with
      # the statistics engine.
      def enable
        @disabled = false
        NewRelic::Agent.instance.stats_engine.sql_sampler = self
      end

      # Disable the sql sampler - this also deregisters it
      # with the statistics engine.
      def disable
        @disabled = true
        NewRelic::Agent.instance.stats_engine.remove_sql_sampler(self)
      end


      # This is called when we are done with the transaction.  We've
      # unwound the stack to the top level. It also clears the
      # transaction sample builder so that it won't continue to have
      # scopes appended to it.
      #
      # It sets various instance variables to the finished sample,
      # depending on which settings are active. See `store_sample`
      def notice_scope_empty(time=Time.now)

        @samples_lock.synchronize do
        end
      end

      def notice_sql(sql, config, duration)
        if NewRelic::Agent.is_sql_recorded?
          notice_extra_data(sql, duration, :sql, config, :connection_config)
          if duration > @explain_threshold && @slow_sql
            @slow_sql << sql
          end
        end
      end


      # get the set of collected samples, merging into previous samples,
      # and clear the collected sample list. Truncates samples to a
      # specified @segment_limit to save memory and bandwith
      # transmitting samples to the server.
      def harvest(previous = [], slow_threshold = 2.0)
        return [] if disabled
        result = Array(previous)
        @samples_lock.synchronize do
          result = add_samples_to(result, slow_threshold)
          # clear previous transaction samples
          @slowest_sample = nil
          @random_sample = nil
          @last_sample = nil
        end
        # Truncate the samples at 2100 segments. The UI will clamp them at 2000 segments anyway.
        # This will save us memory and bandwidth.
        result.each { |sample| sample.truncate(@segment_limit) }
        result
      end

      # reset samples without rebooting the web server
      def reset!
      end

      private

    end
  end
end
