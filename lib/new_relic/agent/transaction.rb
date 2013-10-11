# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction/pop'
require 'new_relic/agent/transaction_timings'

module NewRelic
  module Agent
    # This class represents a single transaction (usually mapping to one
    # web request or background job invocation) instrumented by the Ruby agent.
    #
    # @api public
    class Transaction
      # helper module refactored out of the `pop` method
      include Pop

      attr_accessor :start_time  # A Time instance for the start time, never nil
      attr_accessor :apdex_start # A Time instance used for calculating the apdex score, which
      # might end up being @start, or it might be further upstream if
      # we can find a request header for the queue entry time
      attr_accessor(:type, :exceptions, :filtered_params, :force_flag,
                    :jruby_cpu_start, :process_cpu_start, :database_metric_name)
      attr_reader :name
      attr_reader :stats_hash

      # Give the current transaction a request context.  Use this to
      # get the URI and referer.  The request is interpreted loosely
      # as a Rack::Request or an ActionController::AbstractRequest.
      attr_accessor :request

      # Return the currently active transaction, or nil.
      def self.current
        self.stack.last
      end

      def self.parent
        self.stack[-2]
      end

      def self.start(transaction_type, options={})
        txn = Transaction.new(transaction_type, options)
        txn.start(transaction_type)
        self.stack.push(txn)
        return txn
      end

      def self.stop(metric_name=nil, end_time=Time.now)
        txn = self.stack.last
        txn.stop(metric_name, end_time) if txn
        return self.stack.pop
      end

      def self.stack
        TransactionState.get.current_transaction_stack
      end

      def self.in_transaction?
        !self.stack.empty?
      end

      # This is the name of the model currently assigned to database
      # measurements, overriding the default.
      def self.database_metric_name
        current && current.database_metric_name
      end

      def self.referer
        current && current.referer
      end

      def self.agent
        NewRelic::Agent.instance
      end

      def self.freeze_name
        self.current && self.current.freeze_name
      end

      @@java_classes_loaded = false

      if defined? JRuby
        begin
          require 'java'
          java_import 'java.lang.management.ManagementFactory'
          java_import 'com.sun.management.OperatingSystemMXBean'
          @@java_classes_loaded = true
        rescue => e
        end
      end

      attr_reader :depth

      def initialize(type=:controller, options={})
        @type = type
        @start_time = Time.now
        @apdex_start = @start_time
        @jruby_cpu_start = jruby_cpu_time
        @process_cpu_start = process_cpu
        @filtered_params = options[:filtered_params] || {}
        @force_flag = options[:force]
        @request = options[:request]
        @exceptions = {}
        @stats_hash = StatsHash.new
        TransactionState.get.transaction = self
      end

      def noticed_error_ids
        @noticed_error_ids ||= []
      end

      def name=(name)
        if !@name_frozen
          @name = name
        else
          NewRelic::Agent.logger.warn("Attempted to rename transaction to '#{name}' after transaction name was already frozen as '#{@name}'.")
        end
      end

      def name_set?
        @name && @name != NewRelic::Agent::UNKNOWN_METRIC
      end

      def freeze_name
        return if name_frozen?
        @name = NewRelic::Agent.instance.transaction_rules.rename(@name)
        @name_frozen = true
      end

      def name_frozen?
        @name_frozen
      end

      def parent
        has_parent? && self.class.stack[-2]
      end

      def root?
        self.class.stack.size == 1
      end

      def has_parent?
        self.class.stack.size > 1
      end

      # Indicate that we are entering a measured controller action or task.
      # Make sure you unwind every push with a pop call.
      def start(transaction_type)
        @name = NewRelic::Agent::UNKNOWN_METRIC

        transaction_sampler.notice_first_scope_push(start_time)
        sql_sampler.notice_first_scope_push(start_time)

        NewRelic::Agent::StatsEngine::GCProfiler.init
        agent.stats_engine.start_transaction
        transaction_sampler.notice_transaction(uri, filtered_params)
        sql_sampler.notice_transaction(uri, filtered_params)
      end

      # Indicate that you don't want to keep the currently saved transaction
      # information
      def self.abort_transaction!
        current.abort_transaction! if current
      end

      # For the current web transaction, return the path of the URI minus the host part and query string, or nil.
      def uri
        @uri ||= self.class.uri_from_request(@request) unless @request.nil?
      end

      # For the current web transaction, return the full referer, minus the host string, or nil.
      def referer
        @referer ||= self.class.referer_from_request(@request)
      end

      # Call this to ensure that the current transaction is not saved
      def abort_transaction!
        transaction_sampler.ignore_transaction
      end


      # Unwind one stack level.  It knows if it's back at the outermost caller and
      # does the appropriate wrapup of the context.
      def stop(fallback_name=::NewRelic::Agent::UNKNOWN_METRIC, end_time=Time.now)
        @name = fallback_name unless name_set? || name_frozen?
        freeze_name
        log_underflow if @type.nil?

        # these record metrics so need to be done before merging stats
        if self.root?
          # this one records metrics and wants to happen
          # before the transaction sampler is finished
          if traced?
            record_transaction_cpu
            gc_time = NewRelic::Agent::StatsEngine::GCProfiler.capture
          end
          @transaction_trace = transaction_sampler.notice_scope_empty(self, Time.now, gc_time)
          sql_sampler.notice_scope_empty(@name)
          overview_metrics = transaction_overview_metrics
        end

        record_exceptions
        merge_stats_hash

        # these tear everything down so need to be done after merging stats
        if self.root?
          send_transaction_finished_event(start_time, end_time, overview_metrics)
          agent.stats_engine.end_transaction
        end
      end

      def send_transaction_finished_event(start_time, end_time, overview_metrics)
        payload = {
          :name             => @name,
          :type             => @type,
          :start_timestamp  => start_time.to_f,
          :duration         => end_time.to_f - start_time.to_f,
          :overview_metrics => overview_metrics
        }
        agent.events.notify(:transaction_finished, payload)
      end

      def merge_stats_hash
        stats_hash.resolve_scopes!(@name)
        NewRelic::Agent.instance.stats_engine.merge!(stats_hash)
      end

      def record_exceptions
        @exceptions.each do |exception, options|
          options[:metric] = @name
          agent.error_collector.notice_error(exception, options)
        end
      end

      OVERVIEW_SPECS = [
        [:webDuration,      MetricSpec.new('HttpDispatcher')],
        [:queueDuration,    MetricSpec.new('WebFrontend/QueueTime')],
        [:externalDuration, MetricSpec.new('External/allWeb')],
        [:databaseDuration, MetricSpec.new('ActiveRecord/all')],
        [:gcCumulative,     MetricSpec.new("GC/cumulative")],
        [:memcacheDuration, MetricSpec.new('Memcache/allWeb')]
      ]

      def transaction_overview_metrics
        metrics = {}
        stats = @stats_hash
        OVERVIEW_SPECS.each do |(dest_key, spec)|
          metrics[dest_key] = stats[spec].total_call_time if stats.key?(spec)
        end
        metrics
      end

      # If we have an active transaction, notice the error and increment the error metric.
      # Options:
      # * <tt>:request</tt> => Request object to get the uri and referer
      # * <tt>:uri</tt> => The request path, minus any request params or query string.
      # * <tt>:referer</tt> => The URI of the referer
      # * <tt>:metric</tt> => The metric name associated with the transaction
      # * <tt>:request_params</tt> => Request parameters, already filtered if necessary
      # * <tt>:custom_params</tt> => Custom parameters
      # Anything left over is treated as custom params

      def self.notice_error(e, options={})
        request = options.delete(:request)
        if request
          options[:referer] = referer_from_request(request)
          options[:uri] = uri_from_request(request)
        end
        if current
          current.notice_error(e, options)
        else
          agent.error_collector.notice_error(e, options)
        end
      end

      # Do not call this.  Invoke the class method instead.
      def notice_error(e, options={}) # :nodoc:
        params = custom_parameters
        options[:referer] = referer if referer
        options[:request_params] = filtered_params if filtered_params
        options[:uri] = uri if uri
        options.merge!(custom_parameters)
        if !@exceptions.keys.include?(e)
          @exceptions[e] = options
        end
      end

      # Add context parameters to the transaction.  This information will be passed in to errors
      # and transaction traces.  Keys and Values should be strings, numbers or date/times.
      def self.add_custom_parameters(p)
        current.add_custom_parameters(p) if current
      end

      def self.custom_parameters
        (current && current.custom_parameters) ? current.custom_parameters : {}
      end

      def self.set_user_attributes(attributes)
        current.set_user_attributes(attributes) if current
      end

      def self.user_attributes
        (current) ? current.user_attributes : {}
      end

      APDEX_METRIC_SPEC = NewRelic::MetricSpec.new('Apdex').freeze

      def record_apdex(end_time=Time.now, is_error=nil)
        return unless recording_web_transaction? && NewRelic::Agent.is_execution_traced?

        freeze_name
        action_duration = end_time - start_time
        total_duration  = end_time - apdex_start
        is_error = is_error.nil? ? !exceptions.empty? : is_error

        apdex_bucket_global = self.class.apdex_bucket(total_duration,  is_error, apdex_t)
        apdex_bucket_txn    = self.class.apdex_bucket(action_duration, is_error, apdex_t)

        @stats_hash.record(APDEX_METRIC_SPEC, apdex_bucket_global, apdex_t)
        txn_apdex_metric = NewRelic::MetricSpec.new(@name.gsub(/^[^\/]+\//, 'Apdex/'))
        @stats_hash.record(txn_apdex_metric, apdex_bucket_txn, apdex_t)
      end

      def apdex_t
        transaction_specific_apdex_t || Agent.config[:apdex_t]
      end

      def transaction_specific_apdex_t
        key = :web_transactions_apdex
        Agent.config[key] && Agent.config[key][self.name]
      end

      # Yield to a block that is run with a database metric name context.  This means
      # the Database instrumentation will use this for the metric name if it does not
      # otherwise know about a model.  This is re-entrant.
      #
      # * <tt>model</tt> is the DB model class
      # * <tt>method</tt> is the name of the finder method or other method to identify the operation with.
      #
      def with_database_metric_name(model, method)
        previous = @database_metric_name
        model_name = case model
                     when Class
                       model.name
                     when String
                       model
                     else
                       model.to_s
                     end
        @database_metric_name = "ActiveRecord/#{model_name}/#{method}"
        yield
      ensure
        @database_metric_name=previous
      end

      def custom_parameters
        @custom_parameters ||= {}
      end

      def user_attributes
        @user_atrributes ||= {}
      end

      def queue_time
        @apdex_start ? @start_time - @apdex_start : 0
      end

      def add_custom_parameters(p)
        custom_parameters.merge!(p)
      end

      def set_user_attributes(attributes)
        user_attributes.merge!(attributes)
      end

      # Returns truthy if the current in-progress transaction is considered a
      # a web transaction (as opposed to, e.g., a background transaction).
      #
      # @api public
      #
      def self.recording_web_transaction?
        self.current && self.current.recording_web_transaction?
      end

      def self.transaction_type_is_web?(type)
        [:controller, :uri, :rack, :sinatra].include?(type)
      end

      def recording_web_transaction?
        self.class.transaction_type_is_web?(@type)
      end

      # Make a safe attempt to get the referer from a request object, generally successful when
      # it's a Rack request.
      def self.referer_from_request(request)
        if request && request.respond_to?(:referer)
          request.referer.to_s.split('?').first
        end
      end

      # Make a safe attempt to get the URI, without the host and query string.
      def self.uri_from_request(request)
        approximate_uri = case
                          when request.respond_to?(:fullpath) then request.fullpath
                          when request.respond_to?(:path) then request.path
                          when request.respond_to?(:request_uri) then request.request_uri
                          when request.respond_to?(:uri) then request.uri
                          when request.respond_to?(:url) then request.url
                          end
        return approximate_uri[%r{^(https?://.*?)?(/[^?]*)}, 2] || '/' if approximate_uri # '
      end



      def self.record_apdex(end_time, is_error)
        current && current.record_apdex(end_time, is_error)
      end

      def self.apdex_bucket(duration, failed, apdex_t)
        case
        when failed
          :apdex_f
        when duration <= apdex_t
          :apdex_s
        when duration <= 4 * apdex_t
          :apdex_t
        else
          :apdex_f
        end
      end

      private

      def process_cpu
        return nil if defined? JRuby
        p = Process.times
        p.stime + p.utime
      end

      def jruby_cpu_time # :nodoc:
        return nil unless @@java_classes_loaded
        threadMBean = ManagementFactory.getThreadMXBean()
        java_utime = threadMBean.getCurrentThreadUserTime()  # ns
        -1 == java_utime ? 0.0 : java_utime/1e9
      end

      def agent
        NewRelic::Agent.instance
      end

      def transaction_sampler
        agent.transaction_sampler
      end

      def sql_sampler
        agent.sql_sampler
      end
    end
  end
end
