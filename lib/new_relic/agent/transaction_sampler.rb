# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent'
require 'new_relic/control'
require 'new_relic/agent/transaction_sample_builder'
require 'new_relic/agent/transaction/developer_mode_sample_buffer'
require 'new_relic/agent/transaction/force_persist_sample_buffer'
require 'new_relic/agent/transaction/slowest_sample_buffer'

module NewRelic
  module Agent

    # This class contains the logic of sampling a transaction -
    # creation and modification of transaction samples
    class TransactionSampler

      # Module defining methods stubbed out when the agent is disabled
      module Shim #:nodoc:
        def notice_transaction(*args); end
        def notice_first_scope_push(*args); end
        def notice_push_scope(*args); end
        def notice_pop_scope(*args); end
        def notice_scope_empty(*args); end
      end

      attr_reader :last_sample, :dev_mode_sample_buffer, :sample_buffers

      def initialize
        @dev_mode_sample_buffer = NewRelic::Agent::Transaction::DeveloperModeSampleBuffer.new

        @sample_buffers = []
        @sample_buffers << @dev_mode_sample_buffer
        @sample_buffers << NewRelic::Agent::Transaction::SlowestSampleBuffer.new
        @sample_buffers << NewRelic::Agent::Transaction::ForcePersistSampleBuffer.new

        # This lock is used to synchronize access to the @last_sample
        # and related variables. It can become necessary on JRuby or
        # any 'honest-to-god'-multithreaded system
        @samples_lock = Mutex.new

        Agent.config.register_callback(:'transaction_tracer.enabled') do |enabled|
          if enabled
            threshold = Agent.config[:'transaction_tracer.transaction_threshold']
            ::NewRelic::Agent.logger.debug "Transaction tracing threshold is #{threshold} seconds."
          else
            ::NewRelic::Agent.logger.debug "Transaction traces will not be sent to the New Relic service."
          end
        end

        Agent.config.register_callback(:'transaction_tracer.record_sql') do |config|
          if config == 'raw'
            ::NewRelic::Agent.logger.warn("Agent is configured to send raw SQL to the service")
          end
        end
      end

      def enabled?
        Agent.config[:'transaction_tracer.enabled'] || Agent.config[:developer_mode]
      end

      # Creates a new transaction sample builder, unless the
      # transaction sampler is disabled. Takes a time parameter for
      # the start of the transaction sample
      def notice_first_scope_push(time)
        start_builder(time.to_f) if enabled?
      end

      # This delegates to the builder to create a new open transaction
      # segment for the specified scope, beginning at the optionally
      # specified time.
      #
      # Note that in developer mode, this captures a stacktrace for
      # the beginning of each segment, which can be fairly slow
      def notice_push_scope(time=Time.now)
        return unless builder

        segment = builder.trace_entry(time.to_f)
        @sample_buffers.each { |sample_buffer| sample_buffer.visit_segment(segment) }
        return segment
      end

      # Informs the transaction sample builder about the end of a
      # traced scope
      def notice_pop_scope(scope, time = Time.now)
        return unless builder
        raise "frozen already???" if builder.sample.frozen?
        builder.trace_exit(scope, time.to_f)
      end

      # This is called when we are done with the transaction.  We've
      # unwound the stack to the top level. It also clears the
      # transaction sample builder so that it won't continue to have
      # scopes appended to it.
      #
      # It sets various instance variables to the finished sample,
      # depending on which settings are active. See `store_sample`
      def notice_scope_empty(txn, time=Time.now, gc_time=nil)
        last_builder = builder
        last_builder.set_transaction_name(txn.name) if enabled? && last_builder

        return unless last_builder

        last_builder.finish_trace(time.to_f, txn.custom_parameters)
        clear_builder
        return if last_builder.ignored?

        @samples_lock.synchronize do
          @last_sample = last_builder.sample
          @last_sample.set_custom_param(:gc_time, gc_time) if gc_time
          store_sample(@last_sample)
        end
      end

      def store_sample(sample)
        @sample_buffers.each do |sample_buffer|
          sample_buffer.store(sample)
        end
      end

      # Delegates to the builder to store the uri, and
      # parameters if the sampler is active
      def notice_transaction(uri=nil, params={})
        builder.set_transaction_info(uri, params) if enabled? && builder
      end

      # Tells the builder to ignore a transaction, if we are currently
      # creating one. Only causes the sample to be ignored upon end of
      # the transaction, and does not change the metrics gathered
      # outside of the sampler
      def ignore_transaction
        builder.ignore_transaction if builder
      end

      # For developer mode profiling support - delegates to the builder
      def notice_profile(profile)
        builder.set_profile(profile) if builder
      end

      # Sets the CPU time used by a transaction, delegates to the builder
      def notice_transaction_cpu_time(cpu_time)
        builder.set_transaction_cpu_time(cpu_time) if builder
      end

      MAX_DATA_LENGTH = 16384
      # This method is used to record metadata into the currently
      # active segment like a sql query, memcache key, or Net::HTTP uri
      #
      # duration is seconds, float value.
      def notice_extra_data(message, duration, key)
        return unless builder
        segment = builder.current_segment
        if segment
          if key != :sql
            segment[key] = self.class.truncate_message(append_new_message(segment[key],
                                                                          message))
          else
            segment[key] = message
          end
          append_backtrace(segment, duration)
        end
      end

      private :notice_extra_data

      # Truncates the message to `MAX_DATA_LENGTH` if needed, and
      # appends an ellipsis because it makes the trucation clearer in
      # the UI
      def self.truncate_message(message)
        if message.length > (MAX_DATA_LENGTH - 4)
          message[0..MAX_DATA_LENGTH - 4] + '...'
        else
          message
        end
      end

      # Allows the addition of multiple pieces of metadata to one
      # segment - i.e. traced method calls multiple sql queries
      def append_new_message(old_message, message)
        if old_message
          old_message + ";\n" + message
        else
          message
        end
      end

      # Appends a backtrace to a segment if that segment took longer
      # than the specified duration
      def append_backtrace(segment, duration)
        if duration >= Agent.config[:'transaction_tracer.stack_trace_threshold']
          segment[:backtrace] = caller.join("\n")
        end
      end

      # some statements (particularly INSERTS with large BLOBS
      # may be very large; we should trim them to a maximum usable length
      # config is the driver configuration for the connection
      # duration is seconds, float value.
      def notice_sql(sql, config, duration, &explainer)
        if NewRelic::Agent.is_sql_recorded?
          statement = build_database_statement(sql, config, explainer)
          notice_extra_data(statement, duration, :sql)
        end
      end

      def build_database_statement(sql, config, explainer)
        statement = Database::Statement.new(self.class.truncate_message(sql))
        if config
          statement.adapter = config[:adapter]
          statement.config = config
        end
        if Agent.config[:override_sql_obfuscation_adapter]
          statement.adapter = Agent.config[:override_sql_obfuscation_adapter]
        end
        statement.explainer = explainer

        statement
      end

      # Adds non-sql metadata to a segment - generally the memcached key
      #
      # duration is seconds, float value.
      def notice_nosql(key, duration)
        notice_extra_data(key, duration, :key)
      end

      # Set parameters on the current segment.
      def add_segment_parameters( params )
        return unless builder
        params.each { |k,v| builder.current_segment[k] = v }
      end

      # Returns an array of the slowest sample + force persisted samples
      def add_samples_to(result)
        result.concat(harvest_from_sample_buffers)
        result.compact!
        choose_slowest_and_forced_samples(result)
      end

      def choose_slowest_and_forced_samples(result)
        slowest_sample = find_slowest_sample(result)

        result = select_forced(result)
        result << slowest_sample unless slowest_sample.nil?
        result.uniq
      end

      def harvest_from_sample_buffers
        # Was using map + flatten, but ran into mocking issues on 1.9.2 :/
        result = []
        @sample_buffers.each {|buffer| result.concat(buffer.harvest_samples)}
        result
      end

      def select_unforced(samples)
        samples.select {|sample| !sample.force_persist}
      end

      def select_forced(samples)
        samples - select_unforced(samples)
      end

      def find_slowest_sample(samples)
        select_unforced(samples).max {|a,b| a.duration <=> b.duration}
      end

      # get the set of collected samples, merging into previous samples,
      # and clear the collected sample list. Truncates samples to a
      # specified segment_limit to save memory and bandwith
      # transmitting samples to the server.
      def harvest(previous=[])
        return [] if !enabled?
        result = Array(previous)

        @samples_lock.synchronize do
          result = add_samples_to(result)
          @last_sample = nil
        end

        # Clamp the number of TTs we'll keep in memory and send
        result = clamp_number_tts(result, 20) if result.length > 20
        result
      end

      # JON - THIS CODE NEEDS A UNIT TEST
      def clamp_number_tts(tts, limit)
        tts.sort! do |a,b|
          if a.force_persist && b.force_persist
            b.duration <=> a.duration
          elsif a.force_persist
            -1
          elsif b.force_persist
            1
          else
            b.duration <=> a.duration
          end
        end

        tts[0..(limit-1)]
      end

      # reset samples without rebooting the web server (used by dev mode)
      def reset!
        @samples_lock.synchronize do
          @sample_buffers.each { |sample_buffer| sample_buffer.reset! }
          @last_sample = nil
        end
      end

      # Checks to see if the transaction sampler is disabled, if
      # transaction trace recording is disabled by a thread local, or
      # if execution is untraced - if so it clears the transaction
      # sample builder from the thread local, otherwise it generates a
      # new transaction sample builder with the stated time as a
      # starting point and saves it in the thread local variable
      def start_builder(time=nil)
        if !enabled? || !NewRelic::Agent.is_transaction_traced? || !NewRelic::Agent.is_execution_traced?
          clear_builder
        else
          TransactionState.get.transaction_sample_builder ||= TransactionSampleBuilder.new(time)
        end
      end

      # The current thread-local transaction sample builder
      def builder
        TransactionState.get.transaction_sample_builder
      end

      # Sets the thread local variable storing the transaction sample
      # builder to nil to clear it
      def clear_builder
        TransactionState.get.transaction_sample_builder = nil
      end

    end
  end
end
