# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction_timings'
require 'new_relic/agent/instrumentation/queue_time'
require 'new_relic/agent/transaction_metrics'

module NewRelic
  module Agent
    # This class represents a single transaction (usually mapping to one
    # web request or background job invocation) instrumented by the Ruby agent.
    #
    # @api public
    class Transaction

      # for nested transactions
      SUBTRANSACTION_PREFIX        = 'Nested/'.freeze
      CONTROLLER_PREFIX            = 'Controller/'.freeze
      MIDDLEWARE_PREFIX            = 'Middleware/Rack/'.freeze
      TASK_PREFIX                  = 'OtherTransaction/Background/'.freeze
      RACK_PREFIX                  = 'Controller/Rack/'.freeze
      SINATRA_PREFIX               = 'Controller/Sinatra/'.freeze

      CONTROLLER_MIDDLEWARE_PREFIX = 'Controller/Middleware/Rack'.freeze

      NESTED_TRACE_STOP_OPTIONS    = { :metric => true }.freeze
      WEB_TRANSACTION_CATEGORIES   = [:controller, :uri, :rack, :sinatra, :middleware].freeze

      MIDDLEWARE_SUMMARY_METRICS   = ['Middleware/all'.freeze].freeze
      EMPTY_SUMMARY_METRICS        = [].freeze

      EMPTY_STRING                 = ''

      # A Time instance for the start time, never nil
      attr_accessor :start_time

      # A Time instance used for calculating the apdex score, which
      # might end up being @start, or it might be further upstream if
      # we can find a request header for the queue entry time
      attr_accessor :apdex_start

      attr_accessor :exceptions,
                    :filtered_params,
                    :jruby_cpu_start,
                    :process_cpu_start

      # Give the current transaction a request context.  Use this to
      # get the URI and referer.  The request is interpreted loosely
      # as a Rack::Request or an ActionController::AbstractRequest.
      attr_accessor :request

      attr_reader :database_metric_name,
                  :guid,
                  :metrics,
                  :gc_start_snapshot,
                  :category,
                  :name_from_child

      # Populated with the trace sample once this transaction is completed.
      attr_reader :transaction_trace

      # Return the currently active transaction, or nil.
      def self.tl_current
        TransactionState.tl_get.current_transaction
      end

      def self.set_default_transaction_name(name, options = {})#CDP
        txn  = tl_current
        name = make_transaction_name(name, options[:category])

        if txn.frame_stack.empty?
          txn.set_default_transaction_name(name, options)
        else
          txn.frame_stack.last.name = name
          txn.frame_stack.last.category = options[:category] if options[:category]
        end
      end

      def self.set_overriding_transaction_name(name, options = {})#CDP
        txn = tl_current
        return unless txn

        name = make_transaction_name(name, options[:category])

        if txn.frame_stack.empty?
          txn.set_overriding_transaction_name(name, options)
        else
          txn.frame_stack.last.name = name
          txn.frame_stack.last.category = options[:category] if options[:category]

          # Parent transaction also takes this name, but only if they
          # are both/neither web transactions.
          child_is_web_category = transaction_category_is_web?(txn.frame_stack.last.category)
          txn_is_web_category   = transaction_category_is_web?(txn.category)

          if (child_is_web_category == txn_is_web_category)
            txn.name_from_api = name
          end
        end
      end

      def self.make_transaction_name(name, category=nil)
        namer = Instrumentation::ControllerInstrumentation::TransactionNamer
        "#{namer.prefix_for_category(category)}#{name}"
      end

      def self.start(category, options)#CDP
        category ||= :controller
        txn = tl_current

        if txn
          if options[:filtered_params] && !options[:filtered_params].empty?
            txn.filtered_params = options[:filtered_params]
          end

          nested_frame = NewRelic::Agent::MethodTracer::TraceExecutionScoped.trace_execution_scoped_header(Time.now.to_f)
          nested_frame.name = options[:transaction_name]
          nested_frame.category = category
          txn.frame_stack << nested_frame
        else
          txn = Transaction.new(category, options)
          TransactionState.tl_get.reset(txn)
          txn.start
        end

        txn
      end

      def self.best_category#CDP
        tl_current && tl_current.best_category
      end

      def self.stop(end_time=Time.now)#CDP
        txn = tl_current

        if txn.frame_stack.empty?
          txn.stop(end_time)
          TransactionState.tl_get.reset
        else
          nested_frame = txn.frame_stack.pop

          # Parent transaction inherits the name of the first child
          # to complete, if they are both/neither web transactions.
          nested_is_web_category = transaction_category_is_web?(nested_frame.category)
          txn_is_web_category    = transaction_category_is_web?(txn.category)

          if (nested_is_web_category == txn_is_web_category)
            # first child to finish wins
            txn.name_from_child ||= nested_frame.name
          end

          nested_name = nested_transaction_name(nested_frame.name)

          if nested_name.start_with?(MIDDLEWARE_PREFIX)
            summary_metrics = MIDDLEWARE_SUMMARY_METRICS
          else
            summary_metrics = EMPTY_SUMMARY_METRICS
          end

          NewRelic::Agent::MethodTracer::TraceExecutionScoped.trace_execution_scoped_footer(
            nested_frame.start_time.to_f,
            nested_name,
            summary_metrics,
            nested_frame,
            NESTED_TRACE_STOP_OPTIONS,
            end_time.to_f)
        end

        :transaction_stopped
      end

      def self.nested_transaction_name(name)
        if name.start_with?(CONTROLLER_PREFIX)
          "#{SUBTRANSACTION_PREFIX}#{name}"
        else
          name
        end
      end

      def self.ignore!#CDP
        tl_current && tl_current.ignore!
      end

      def self.ignore?#CDP
        tl_current && tl_current.ignore?
      end

      def self.ignore_apdex!#CDP
        tl_current && tl_current.ignore_apdex!
      end

      def self.ignore_apdex?#CDP
        tl_current && tl_current.ignore_apdex?
      end

      def self.ignore_enduser!#CDP
        tl_current && tl_current.ignore_enduser!
      end

      def self.ignore_enduser?#CDP
        tl_current && tl_current.ignore_enduser?
      end

      # This is the name of the model currently assigned to database
      # measurements, overriding the default.
      def self.database_metric_name#CDP
        tl_current && tl_current.database_metric_name
      end

      def self.referer#CDP
        tl_current && tl_current.referer
      end

      def self.agent
        NewRelic::Agent.instance
      end

      def self.freeze_name_and_execute_if_not_ignored#CDP
        tl_current && tl_current.freeze_name_and_execute_if_not_ignored { yield if block_given? }
      end

      @@java_classes_loaded = false

      if defined? JRuby
        begin
          require 'java'
          java_import 'java.lang.management.ManagementFactory'
          java_import 'com.sun.management.OperatingSystemMXBean'
          @@java_classes_loaded = true
        rescue
        end
      end

      attr_reader :frame_stack

      def initialize(category, options)
        @frame_stack = []

        @default_name    = Helper.correctly_encoded(options[:transaction_name])
        @name_from_child = nil
        @name_from_api   = nil
        @frozen_name     = nil

        @category = category
        @start_time = Time.now
        @apdex_start = options[:apdex_start_time] || @start_time
        @jruby_cpu_start = jruby_cpu_time
        @process_cpu_start = process_cpu
        @gc_start_snapshot = NewRelic::Agent::StatsEngine::GCProfiler.take_snapshot
        @filtered_params = options[:filtered_params] || {}
        @request = options[:request]
        @exceptions = {}
        @metrics = TransactionMetrics.new
        @guid = generate_guid

        @ignore_this_transaction = false
        @ignore_apdex = false
        @ignore_enduser = false
      end

      def noticed_error_ids
        @noticed_error_ids ||= []
      end

      def default_name=(name)
        @default_name = Helper.correctly_encoded(name)
      end

      def name_from_child=(name)
        @name_from_child = Helper.correctly_encoded(name)
      end

      def name_from_api=(name)
        if @frozen_name
          NewRelic::Agent.logger.warn("Attempted to rename transaction to '#{name}' after transaction name was already frozen as '#{@frozen_name}'.")
        end

        @name_from_api = Helper.correctly_encoded(name)
      end

      def set_default_transaction_name(name, options)
        self.default_name = name
        @category = options[:category] if options[:category]
      end

      def set_overriding_transaction_name(name, options)
        self.name_from_api = name
        set_default_transaction_name(name, options)
      end

      def best_category
        if frame_stack.empty?
          category
        else
          frame_stack.last.category
        end
      end

      def best_name
        return @frozen_name   if @frozen_name
        return @name_from_api if @name_from_api

        if @name_from_child
          return @name_from_child
        elsif !@frame_stack.empty?
          return @frame_stack.last.name
        end

        return @default_name if @default_name

        NewRelic::Agent::UNKNOWN_METRIC
      end

      def name_set?
        (@name_from_api || @name_from_child || @default_name) ? true : false
      end

      def promoted_transaction_name(name)
        if name.start_with?(MIDDLEWARE_PREFIX)
          "#{CONTROLLER_PREFIX}#{name}"
        else
          name
        end
      end

      def freeze_name_and_execute_if_not_ignored
        if !name_frozen?
          name = promoted_transaction_name(best_name)
          name = NewRelic::Agent.instance.transaction_rules.rename(name)
          @name_frozen = true

          if name.nil?
            ignore!
            @frozen_name = best_name
          else
            @frozen_name = name
          end
        end

        if block_given? && !@ignore_this_transaction
          yield
        end
      end

      def name_frozen?
        @frozen_name ? true : false
      end

      def ignored?
        @ignore_this_transaction
      end

      # Indicate that we are entering a measured controller action or task.
      # Make sure you unwind every push with a pop call.
      def start#CDP
        state = NewRelic::Agent::TransactionState.tl_get
        return if !state.is_execution_traced?

        transaction_sampler.on_start_transaction(state, start_time, uri, filtered_params)
        sql_sampler.on_start_transaction(state, start_time, uri, filtered_params)
        NewRelic::Agent.instance.events.notify(:start_transaction)
        NewRelic::Agent::BusyCalculator.dispatcher_start(start_time)

        @trace_options = { :metric => true, :scoped_metric => false }
        @expected_scope = NewRelic::Agent::MethodTracer::TraceExecutionScoped.trace_execution_scoped_header(start_time.to_f)
      end

      # Indicate that you don't want to keep the currently saved transaction
      # information
      def self.abort_transaction!#CDP
        tl_current.abort_transaction! if tl_current
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
      def abort_transaction!#CDP
        state = NewRelic::Agent::TransactionState.tl_get
        transaction_sampler.ignore_transaction(state)
      end

      def summary_metrics
        metrics = []

        if @frozen_name.start_with?(CONTROLLER_MIDDLEWARE_PREFIX)
          metrics.concat(MIDDLEWARE_SUMMARY_METRICS)
        end

        metric_parser = NewRelic::MetricParser::MetricParser.for_metric_named(@frozen_name)
        metrics.concat(metric_parser.summary_metrics)

        metrics
      end

      def stop(end_time)#CDP
        state = NewRelic::Agent::TransactionState.tl_get
        return if !state.is_execution_traced?
        freeze_name_and_execute_if_not_ignored

        name    = @frozen_name
        metrics = summary_metrics

        if @name_from_child
          name = Transaction.nested_transaction_name(@default_name)
          metrics << @frozen_name
          @trace_options[:scoped_metric] = true
        end

        NewRelic::Agent::MethodTracer::TraceExecutionScoped.trace_execution_scoped_footer(
          start_time.to_f,
          name,
          metrics,
          @expected_scope,
          @trace_options,
          end_time.to_f)

        NewRelic::Agent::BusyCalculator.dispatcher_finish(end_time)

        unless @ignore_this_transaction
          # these record metrics so need to be done before merging stats

          # this one records metrics and wants to happen
          # before the transaction sampler is finished
          record_transaction_cpu
          gc_stop_snapshot = NewRelic::Agent::StatsEngine::GCProfiler.take_snapshot
          gc_delta = NewRelic::Agent::StatsEngine::GCProfiler.record_delta(
              gc_start_snapshot, gc_stop_snapshot)
          @transaction_trace = transaction_sampler.on_finishing_transaction(state, self, Time.now, gc_delta)
          sql_sampler.on_finishing_transaction(state, @frozen_name)

          record_apdex(end_time) unless ignore_apdex?
          NewRelic::Agent::Instrumentation::QueueTime.record_frontend_metrics(apdex_start, start_time) if queue_time > 0.0

          record_exceptions
          merge_metrics

          send_transaction_finished_event(start_time, end_time)
        end
      end

      # This event is fired when the transaction is fully completed. The metric
      # values and sampler can't be successfully modified from this event.
      def send_transaction_finished_event(start_time, end_time)
        payload = {
          :name             => @frozen_name,
          :start_timestamp  => start_time.to_f,
          :duration         => end_time.to_f - start_time.to_f,
          :metrics          => @metrics,
          :custom_params    => custom_parameters
        }
        append_guid_to(payload)
        append_referring_transaction_guid_to(payload)

        agent.events.notify(:transaction_finished, payload)
      end

      def append_guid_to(payload)#CDP
        guid = NewRelic::Agent::TransactionState.tl_get.request_guid_for_event
        if guid
          payload[:guid] = guid
        end
      end

      def append_referring_transaction_guid_to(payload)
        referring_guid = NewRelic::Agent.instance.cross_app_monitor.client_referring_transaction_guid
        if referring_guid
          payload[:referring_transaction_guid] = referring_guid
        end
      end

      def merge_metrics
        NewRelic::Agent.instance.stats_engine.merge_transaction_metrics!(@metrics, best_name)
      end

      def record_exceptions
        @exceptions.each do |exception, options|
          options[:metric] = best_name
          agent.error_collector.notice_error(exception, options)
        end
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

      def self.notice_error(e, options={})#CDP
        options = extract_request_options(options)
        if tl_current
          tl_current.notice_error(e, options)
        else
          options = extract_finished_transaction_options(options)
          agent.error_collector.notice_error(e, options)
        end
      end

      def self.extract_request_options(options)
        req = options.delete(:request)
        if req
          options[:referer] = referer_from_request(req)
          options[:uri] = uri_from_request(req)
        end
        options
      end

      # If we aren't currently in a transaction, but found the remains of one
      # just finished in the TransactionState, use those custom params!
      def self.extract_finished_transaction_options(options)#CDP
        finished_txn = NewRelic::Agent::Transaction.tl_current
        if finished_txn
          custom_params = options.fetch(:custom_params, {})
          custom_params.merge!(finished_txn.custom_parameters)
          options = options.merge(:custom_params => custom_params)
          options[:metric] = finished_txn.best_name
        end
        options
      end

      # Do not call this.  Invoke the class method instead.
      def notice_error(error, options={}) # :nodoc:
        options[:referer] = referer if referer

        if filtered_params && !filtered_params.empty?
          options[:request_params] = filtered_params
        end

        options[:uri] = uri if uri
        options.merge!(custom_parameters)

        if @exceptions.keys.include?(error)
          @exceptions[error].merge! options
        else
          @exceptions[error] = options
        end
      end

      # Add context parameters to the transaction.  This information will be passed in to errors
      # and transaction traces.  Keys and Values should be strings, numbers or date/times.
      def self.add_custom_parameters(p)#CDP
        tl_current.add_custom_parameters(p) if tl_current
      end

      def self.custom_parameters#CDP
        (tl_current && tl_current.custom_parameters) ? tl_current.custom_parameters : {}
      end

      class << self
        alias_method :user_attributes, :custom_parameters
        alias_method :set_user_attributes, :add_custom_parameters
      end

      APDEX_METRIC = 'Apdex'.freeze

      def record_apdex(end_time=Time.now)#CDP
        return unless recording_web_transaction? && NewRelic::Agent.tl_is_execution_traced?

        freeze_name_and_execute_if_not_ignored do
          action_duration = end_time - start_time
          total_duration  = end_time - apdex_start
          is_error = !notable_exceptions.empty?

          apdex_bucket_global = self.class.apdex_bucket(total_duration,  is_error, apdex_t)
          apdex_bucket_txn    = self.class.apdex_bucket(action_duration, is_error, apdex_t)

          @metrics.record_unscoped(APDEX_METRIC, apdex_bucket_global, apdex_t)
          txn_apdex_metric = @frozen_name.gsub(/^[^\/]+\//, 'Apdex/')
          @metrics.record_unscoped(txn_apdex_metric, apdex_bucket_txn, apdex_t)
        end
      end

      def apdex_t
        transaction_specific_apdex_t || Agent.config[:apdex_t]
      end

      def transaction_specific_apdex_t
        key = :web_transactions_apdex
        Agent.config[key] && Agent.config[key][best_name]
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

      def add_custom_parameters(p)
        custom_parameters.merge!(p)
      end

      alias_method :user_attributes, :custom_parameters
      alias_method :set_user_attributes, :add_custom_parameters

      def queue_time
        @apdex_start ? @start_time - @apdex_start : 0
      end

      # Returns truthy if the current in-progress transaction is considered a
      # a web transaction (as opposed to, e.g., a background transaction).
      #
      # @api public
      #
      def self.recording_web_transaction?#CDP
        tl_current && tl_current.recording_web_transaction?
      end

      def self.transaction_category_is_web?(category)
        WEB_TRANSACTION_CATEGORIES.include?(category)
      end

      def recording_web_transaction?
        self.class.transaction_category_is_web?(@category)
      end

      # Make a safe attempt to get the referer from a request object, generally successful when
      # it's a Rack request.
      def self.referer_from_request(req)
        if req && req.respond_to?(:referer)
          req.referer.to_s.split('?').first
        end
      end

      # Make a safe attempt to get the URI, without the host and query string.
      def self.uri_from_request(req)
        approximate_uri = case
                          when req.respond_to?(:fullpath   ) then req.fullpath
                          when req.respond_to?(:path       ) then req.path
                          when req.respond_to?(:request_uri) then req.request_uri
                          when req.respond_to?(:uri        ) then req.uri
                          when req.respond_to?(:url        ) then req.url
                          end
        return approximate_uri[%r{^(https?://.*?)?(/[^?]*)}, 2] || '/' if approximate_uri
      end


      def self.record_apdex(end_time)#CDP
        tl_current && tl_current.record_apdex(end_time)
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

      def cpu_burn
        normal_cpu_burn || jruby_cpu_burn
      end

      def normal_cpu_burn
        return unless @process_cpu_start
        process_cpu - @process_cpu_start
      end

      def jruby_cpu_burn
        return unless @jruby_cpu_start
        jruby_cpu_time - @jruby_cpu_start
      end

      def record_transaction_cpu#CDP
        burn = cpu_burn
        if burn
          state = NewRelic::Agent::TransactionState.tl_get
          transaction_sampler.notice_transaction_cpu_time(state, burn)
        end
      end

      def ignore!
        @ignore_this_transaction = true
      end

      def ignore?
        @ignore_this_transaction
      end

      def ignore_apdex!
        @ignore_apdex = true
      end

      def ignore_apdex?
        @ignore_apdex
      end

      def ignore_enduser!
        @ignore_enduser = true
      end

      def ignore_enduser?
        @ignore_enduser
      end

      def notable_exceptions
        @exceptions.keys.select do |exception|
          !NewRelic::Agent.instance.error_collector.error_is_ignored?(exception)
        end
      end

      private

      def process_cpu
        return nil if defined? JRuby
        p = Process.times
        p.stime + p.utime
      end

      def jruby_cpu_time
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

      HEX_DIGITS = (0..15).map{|i| i.to_s(16)}
      GUID_LENGTH = 16

      # generate a random 64 bit uuid
      def generate_guid
        guid = ''
        GUID_LENGTH.times do |a|
          guid << HEX_DIGITS[rand(16)]
        end
        guid
      end

    end
  end
end
