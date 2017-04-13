# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction_sample_builder'
require 'new_relic/agent/transaction/slowest_sample_buffer'
require 'new_relic/agent/transaction/synthetics_sample_buffer'
require 'new_relic/agent/transaction/xray_sample_buffer'
require 'new_relic/agent/transaction/trace_builder'

module NewRelic
  module Agent

    # This class contains the logic for recording and storing transaction
    # traces (sometimes referred to as 'transaction samples').
    #
    # A transaction trace is a detailed timeline of the events that happened
    # during the processing of a single transaction, including database calls,
    # template rendering calls, and other instrumented method calls.
    #
    # @api public
    class TransactionSampler
      attr_reader :last_sample, :xray_sample_buffer

      def initialize
        @xray_sample_buffer = NewRelic::Agent::Transaction::XraySampleBuffer.new

        @sample_buffers = []
        @sample_buffers << @xray_sample_buffer
        @sample_buffers << NewRelic::Agent::Transaction::SlowestSampleBuffer.new
        @sample_buffers << NewRelic::Agent::Transaction::SyntheticsSampleBuffer.new

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
        Agent.config[:'transaction_tracer.enabled']
      end

      # This delegates to the builder to create a new open transaction node
      # for the frame, beginning at the optionally specified time.
      def notice_push_frame(state, time=Time.now)
        builder = state.transaction_sample_builder
        return unless builder

        builder.trace_entry(time.to_f)
      end

      # Informs the transaction sample builder about the end of a traced frame
      def notice_pop_frame(state, frame, time = Time.now)
        builder = state.transaction_sample_builder
        return unless builder
        raise "finished already???" if builder.sample.finished
        builder.trace_exit(frame, time.to_f)
      end

      # This is called when we are done with the transaction.  We've
      # unwound the stack to the top level. It also clears the
      # transaction sample builder so that it won't continue to have
      # frames appended to it.
      #
      # It sets various instance variables to the finished sample,
      # depending on which settings are active. See `store_sample`
      def on_finishing_transaction(state, txn, time=Time.now)
        return if !enabled? || txn.ignore_trace?

        last_sample = NewRelic::Agent::Transaction::TraceBuilder.build_trace txn

        last_sample.transaction_name = txn.best_name
        last_sample.uri = txn.request_path
        last_sample.guid = txn.guid
        last_sample.attributes = txn.attributes
        last_sample.threshold = transaction_trace_threshold
        last_sample.finished = true

        @samples_lock.synchronize do
          @last_sample = last_sample
          store_sample(@last_sample)
          @last_sample
        end
      end

      def store_sample(sample)
        @sample_buffers.each do |sample_buffer|
          sample_buffer.store(sample)
        end
      end

      # Set parameters on the current node.
      def add_node_parameters(params) #THREAD_LOCAL_ACCESS
        builder = tl_builder
        return unless builder
        params.each { |k,v| builder.current_node[k] = v }
      end

      # Gather transaction traces that we'd like to transmit to the server.
      def harvest!
        return [] unless enabled?

        samples = @samples_lock.synchronize do
          @last_sample = nil
          harvest_from_sample_buffers
        end
        prepare_samples(samples)
      end

      def prepare_samples(samples)
        samples.select do |sample|
          begin
            sample.prepare_to_send!
          rescue => e
            NewRelic::Agent.logger.error("Failed to prepare transaction trace. Error: ", e)
            false
          else
            true
          end
        end
      end

      def merge!(previous)
        @samples_lock.synchronize do
          @sample_buffers.each do |buffer|
            buffer.store_previous(previous)
          end
        end
      end

      def count
        @samples_lock.synchronize do
          samples = @sample_buffers.inject([]) { |all, b| all.concat(b.samples) }
          samples.uniq.size
        end
      end

      def harvest_from_sample_buffers
        # map + flatten hit mocking issues calling to_ary on 1.9.2.  We only
        # want a single level flatten anyway, but, as you probably already
        # know, Ruby 1.8.6 :/
        result = []
        @sample_buffers.each { |buffer| result.concat(buffer.harvest_samples) }
        result.uniq
      end

      # reset samples without rebooting the web server (used by dev mode)
      def reset!
        @samples_lock.synchronize do
          @last_sample = nil
          @sample_buffers.each { |sample_buffer| sample_buffer.reset! }
        end
      end

      # Checks to see if the transaction sampler is disabled, if
      # transaction trace recording is disabled by a thread local, or
      # if execution is untraced - if so it clears the transaction
      # sample builder from the thread local, otherwise it generates a
      # new transaction sample builder with the stated time as a
      # starting point and saves it in the thread local variable
      def start_builder(state, time=nil)
        if !enabled? || !state.is_transaction_traced? || !state.is_execution_traced?
          state.transaction_sample_builder = nil
        else
          state.transaction_sample_builder ||= TransactionSampleBuilder.new(time)
        end
      end

      # The current thread-local transaction sample builder
      def tl_builder
        TransactionState.tl_get.transaction_sample_builder
      end

      TT_THRESHOLD_KEY = :'transaction_tracer.transaction_threshold'

      def transaction_trace_threshold #THREAD_LOCAL_ACCESS
        state = TransactionState.tl_get
        source_class = Agent.config.source(TT_THRESHOLD_KEY).class
        if source_class == Configuration::DefaultSource && state.current_transaction
          state.current_transaction.apdex_t * 4
        else
          Agent.config[TT_THRESHOLD_KEY]
        end
      end
    end
  end
end
