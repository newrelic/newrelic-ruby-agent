# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction_sample_builder'
require 'new_relic/agent/transaction/developer_mode_sample_buffer'
require 'new_relic/agent/transaction/slowest_sample_buffer'
require 'new_relic/agent/transaction/synthetics_sample_buffer'
require 'new_relic/agent/transaction/xray_sample_buffer'

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
      attr_reader :last_sample, :dev_mode_sample_buffer, :xray_sample_buffer

      def initialize
        @dev_mode_sample_buffer = NewRelic::Agent::Transaction::DeveloperModeSampleBuffer.new
        @xray_sample_buffer = NewRelic::Agent::Transaction::XraySampleBuffer.new

        @sample_buffers = []
        @sample_buffers << @dev_mode_sample_buffer
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
        Agent.config[:'transaction_tracer.enabled'] || Agent.config[:developer_mode]
      end

      def on_start_transaction(state, start_time)
        if enabled?
          start_builder(state, start_time.to_f)
        end
      end

      # This delegates to the builder to create a new open transaction node
      # for the frame, beginning at the optionally specified time.
      #
      # Note that in developer mode, this captures a stacktrace for
      # the beginning of each node, which can be fairly slow
      def notice_push_frame(state, time=Time.now)
        builder = state.transaction_sample_builder
        return unless builder

        node = builder.trace_entry(time.to_f)
        if @dev_mode_sample_buffer
          @dev_mode_sample_buffer.visit_node(node)
        end
        node
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
        last_builder = state.transaction_sample_builder
        return unless last_builder && enabled?

        state.transaction_sample_builder = nil
        return if txn.ignore_trace?

        last_builder.finish_trace(time.to_f)

        last_sample = last_builder.sample
        last_sample.transaction_name = txn.best_name
        last_sample.uri = txn.request_path
        last_sample.guid = txn.guid
        last_sample.attributes = txn.attributes

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

      MAX_DATA_LENGTH = 16384
      # This method is used to record metadata into the currently
      # active node like a sql query, memcache key, or Net::HTTP uri
      #
      # duration is seconds, float value.
      def notice_extra_data(builder, message, duration, key)
        return unless builder
        node = builder.current_node
        if node
          if key == :sql
            statement = node[:sql]
            if(statement && !statement.sql.empty?)
              statement.sql = self.class.truncate_message(statement.sql + "\n#{message.sql}") if statement.sql.length <= MAX_DATA_LENGTH
            else
              # message is expected to have been pre-truncated by notice_sql
              node[:sql] = message
            end
          else
            node[key] = self.class.truncate_message(message)
          end
          append_backtrace(node, duration)
        end
      end

      private :notice_extra_data

      # Truncates the message to `MAX_DATA_LENGTH` if needed, and
      # appends an ellipsis because it makes the trucation clearer in
      # the UI
      def self.truncate_message(message)
        if message.length > (MAX_DATA_LENGTH - 4)
          message.slice!(MAX_DATA_LENGTH - 4..message.length)
          message << "..."
        else
          message
        end
      end

      # Appends a backtrace to a node if that node took longer
      # than the specified duration
      def append_backtrace(node, duration)
        if duration >= Agent.config[:'transaction_tracer.stack_trace_threshold']
          node[:backtrace] = caller.join("\n")
        end
      end

      # Attaches an SQL query on the current transaction trace node.
      #
      # This method should be used only by gem authors wishing to extend
      # the Ruby agent to instrument new database interfaces - it should
      # generally not be called directly from application code.
      #
      # @param sql [String] the SQL query being recorded
      # @param config [Object] the driver configuration for the connection
      # @param duration [Float] number of seconds the query took to execute
      # @param explainer [Proc] for internal use only - 3rd-party clients must
      #                         not pass this parameter.
      #
      # @api public
      # @deprecated Use {Datastores.notice_sql} instead.
      #
      def notice_sql(sql, config, duration, state=nil, explainer=nil, binds=[], name="SQL") #THREAD_LOCAL_ACCESS sometimes
        # some statements (particularly INSERTS with large BLOBS
        # may be very large; we should trim them to a maximum usable length
        state ||= TransactionState.tl_get
        builder = state.transaction_sample_builder
        if state.is_sql_recorded?
          statement = Database::Statement.new(sql, config, explainer, binds, name)
          notice_extra_data(builder, statement, duration, :sql)
        end
      end

      # Attaches an additional non-SQL query parameter to the current
      # transaction trace node.
      #
      # This may be used for recording a query against a key-value store like
      # memcached or redis.
      #
      # This method should be used only by gem authors wishing to extend
      # the Ruby agent to instrument uninstrumented key-value stores - it should
      # generally not be called directly from application code.
      #
      # @param key [String] the name of the key that was queried
      # @param duration [Float] number of seconds the query took to execute
      #
      # @api public
      # @deprecated Use {Datastores.notice_statement} instead.
      #
      def notice_nosql(key, duration) #THREAD_LOCAL_ACCESS
        builder = tl_builder
        notice_extra_data(builder, key, duration, :key)
      end

      def notice_nosql_statement(statement, duration) #THREAD_LOCAL_ACCESS
        builder = tl_builder
        notice_extra_data(builder, statement, duration, :statement)
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
    end
  end
end
