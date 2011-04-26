require 'new_relic/agent'
require 'new_relic/control'
require 'new_relic/agent/transaction_sample_builder'
module NewRelic
  module Agent

    class TransactionSampler

      # Module defining methods stubbed out when the agent is disabled
      module Shim #:nodoc:
        def notice_first_scope_push(*args); end
        def notice_push_scope(*args); end
        def notice_pop_scope(*args); end
        def notice_scope_empty(*args); end
      end

      BUILDER_KEY = :transaction_sample_builder

      attr_accessor :stack_trace_threshold, :random_sampling, :sampling_rate
      attr_reader :samples, :last_sample, :disabled

      def initialize
        @samples = []
        @harvest_count = 0
        @max_samples = 100
        @random_sample = nil
        config = NewRelic::Control.instance
        sampler_config = config.fetch('transaction_tracer', {})
        @segment_limit = sampler_config.fetch('limit_segments', 4000)
        @stack_trace_threshold = sampler_config.fetch('stack_trace_threshold', 0.500).to_f
        @samples_lock = Mutex.new
      end

      def current_sample_id
        b=builder
        b and b.sample_id
      end

      def enable
        @disabled = false
        NewRelic::Agent.instance.stats_engine.transaction_sampler = self
      end

      def disable
        @disabled = true
        NewRelic::Agent.instance.stats_engine.remove_transaction_sampler(self)
      end

      def sampling_rate=(val)
        @sampling_rate = val.to_i
        @harvest_count = rand(val.to_i).to_i
      end

      def notice_first_scope_push(time)
        start_builder(time.to_f) unless disabled
      end

      def notice_push_scope(scope, time=Time.now)
        return unless builder

        builder.trace_entry(scope, time.to_f)

        capture_segment_trace if NewRelic::Control.instance.developer_mode?
      end
      
      # in developer mode, capture the stack trace with the segment.
      # this is cpu and memory expensive and therefore should not be
      # turned on in production mode
      def capture_segment_trace
        return unless NewRelic::Control.instance.developer_mode?
        segment = builder.current_segment
        if segment
          # Strip stack frames off the top that match /new_relic/agent/
          trace = caller
          while trace.first =~/\/lib\/new_relic\/agent\//
            trace.shift
          end

          trace = trace[0..39] if trace.length > 40
          segment[:backtrace] = trace
        end
      end

      def scope_depth
        return 0 unless builder

        builder.scope_depth
      end

      def notice_pop_scope(scope, time = Time.now)
        return unless builder
        raise "frozen already???" if builder.sample.frozen?
        builder.trace_exit(scope, time.to_f)
      end

      # This is called when we are done with the transaction.  We've
      # unwound the stack to the top level.
      def notice_scope_empty(time=Time.now)

        last_builder = builder
        return unless last_builder

        last_builder.finish_trace(time.to_f)
        clear_builder
        return if last_builder.ignored?

        @samples_lock.synchronize do
          # NB this instance variable may be used elsewhere, it's not
          # just a side effect
          @last_sample = last_builder.sample
          store_sample(@last_sample)
        end
      end
      
      def store_sample(sample)
        store_random_sample(sample)
        store_sample_for_developer_mode(sample)
        store_slowest_sample(sample)
      end

      def store_random_sample(sample)
        if @random_sampling
          @random_sample = sample
        end
      end
      
      def store_sample_for_developer_mode(sample)
        return unless NewRelic::Control.instance.developer_mode?
        @samples = [] unless @samples
        @samples << sample
        truncate_samples
      end

      def store_slowest_sample(sample)
        @slowest_sample = sample if slowest_sample?(@slowest_sample, sample)
      end

      def slowest_sample?(old_sample, new_sample)
        old_sample.nil? || (new_sample.duration > old_sample.duration)
      end

      def truncate_samples
        if @samples.length > @max_samples
          @samples = @samples[-@max_samples..-1]
        end
      end

      def notice_transaction(path, uri=nil, params={})
        builder.set_transaction_info(path, uri, params) if !disabled && builder
      end

      def ignore_transaction
        builder.ignore_transaction if builder
      end
      def notice_profile(profile)
        builder.set_profile(profile) if builder
      end

      def notice_transaction_cpu_time(cpu_time)
        builder.set_transaction_cpu_time(cpu_time) if builder
      end

      MAX_DATA_LENGTH = 16384
      # duration is seconds, float value.
      def notice_extra_data(message, duration, key, config=nil, config_key=nil)
        return unless builder
        segment = builder.current_segment
        if segment
          segment[key] = truncate_message(append_new_message(segment[key], message))
          segment[config_key] = config if config_key
          append_backtrace(segment, duration)
        end
      end

      private :notice_extra_data
      
      def truncate_message(message)
        if message.length > (MAX_DATA_LENGTH - 4)
          message[0..MAX_DATA_LENGTH - 4] + '...'
        else
          message
        end
      end

      def append_new_message(old_message, message)
        if old_message
          old_message + ";\n" + message
        else
          message
        end
      end

      def append_backtrace(segment, duration)
        segment[:backtrace] = caller.join("\n") if duration >= @stack_trace_threshold
      end

      # some statements (particularly INSERTS with large BLOBS
      # may be very large; we should trim them to a maximum usable length
      # config is the driver configuration for the connection
      # duration is seconds, float value.
      def notice_sql(sql, config, duration)
        if Thread::current[:record_sql] != false
          notice_extra_data(sql, duration, :sql, config, :connection_config)
        end
      end

      # duration is seconds, float value.
      def notice_nosql(key, duration)
        notice_extra_data(key, duration, :key)
      end
      
      # random sampling is very, very seldom used
      def add_random_sample_to(result)
        return unless @random_sampling
        @harvest_count += 1
        if (@harvest_count.to_i % @sampling_rate.to_i) == 0
          result << @random_sample if @random_sample
        end
        result.uniq!
        nil # don't assume this method returns anything
      end

      def add_samples_to(result, slow_threshold)
        if @slowest_sample && @slowest_sample.duration >= slow_threshold
          result << @slowest_sample
        end
        result.compact!
        result = result.sort_by { |x| x.duration }
        result = result[-1..-1] || []
        add_random_sample_to(result)
        result
      end

      # get the set of collected samples, merging into previous samples,
      # and clear the collected sample list.
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
        @samples = []
        @last_sample = nil
        @random_sample = nil
        @slowest_sample = nil
      end

      private

      def start_builder(time=nil)
        if disabled || Thread::current[:record_tt] == false || !NewRelic::Agent.is_execution_traced?
          clear_builder
        else
          Thread::current[BUILDER_KEY] ||= TransactionSampleBuilder.new(time)
        end
      end
      def builder
        Thread::current[BUILDER_KEY]
      end
      def clear_builder
        Thread::current[BUILDER_KEY] = nil
      end

    end
  end
end
