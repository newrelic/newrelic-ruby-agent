# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction_timings'
require 'new_relic/agent/instrumentation/queue_time'
require 'new_relic/agent/transaction_metrics'
require 'new_relic/agent/method_tracer_helpers'
require 'new_relic/agent/transaction/attributes'
require 'new_relic/agent/transaction/request_attributes'

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
      RAKE_PREFIX                  = 'OtherTransaction/Rake/'.freeze
      RACK_PREFIX                  = 'Controller/Rack/'.freeze
      SINATRA_PREFIX               = 'Controller/Sinatra/'.freeze
      GRAPE_PREFIX                 = 'Controller/Grape/'.freeze
      OTHER_TRANSACTION_PREFIX     = 'OtherTransaction/'.freeze

      CONTROLLER_MIDDLEWARE_PREFIX = 'Controller/Middleware/Rack'.freeze

      NESTED_TRACE_STOP_OPTIONS    = { :metric => true }.freeze
      WEB_TRANSACTION_CATEGORIES   = [:controller, :uri, :rack, :sinatra, :grape, :middleware].freeze
      TRANSACTION_NAMING_SOURCES   = [:child, :api].freeze

      MIDDLEWARE_SUMMARY_METRICS   = ['Middleware/all'.freeze].freeze
      EMPTY_SUMMARY_METRICS        = [].freeze

      TRACE_OPTIONS_SCOPED         = { :metric => true, :scoped_metric => true }.freeze
      TRACE_OPTIONS_UNSCOPED       = { :metric => true, :scoped_metric => false }.freeze

      # A Time instance for the start time, never nil
      attr_accessor :start_time

      # A Time instance used for calculating the apdex score, which
      # might end up being @start, or it might be further upstream if
      # we can find a request header for the queue entry time
      attr_accessor :apdex_start

      attr_accessor :exceptions,
                    :filtered_params,
                    :jruby_cpu_start,
                    :process_cpu_start,
                    :http_response_code,
                    :response_content_length,
                    :response_content_type

      attr_reader :guid,
                  :metrics,
                  :gc_start_snapshot,
                  :category,
                  :frame_stack,
                  :cat_path_hashes,
                  :attributes,
                  :payload

      # Populated with the trace sample once this transaction is completed.
      attr_reader :transaction_trace

      # Fields for tracking synthetics requests
      attr_accessor :raw_synthetics_header, :synthetics_payload

      # Return the currently active transaction, or nil.
      def self.tl_current
        TransactionState.tl_get.current_transaction
      end

      def self.set_default_transaction_name(name, category = nil, node_name = nil) #THREAD_LOCAL_ACCESS
        txn  = tl_current
        name = txn.make_transaction_name(name, category)
        txn.name_last_frame(node_name || name)
        txn.set_default_transaction_name(name, category)
      end

      def self.set_overriding_transaction_name(name, category = nil) #THREAD_LOCAL_ACCESS
        txn = tl_current
        return unless txn

        name = txn.make_transaction_name(name, category)

        txn.name_last_frame(name)
        txn.set_overriding_transaction_name(name, category)
      end

      def self.wrap(state, name, category, options = {})
        Transaction.start(state, category, options.merge(:transaction_name => name))

        begin
          # We shouldn't raise from Transaction.start, but only wrap the yield
          # to be absolutely sure we don't report agent problems as app errors
          yield
        rescue => e
          Transaction.notice_error(e)
          raise e
        ensure
          Transaction.stop(state)
        end
      end

      def self.start(state, category, options)
        category ||= :controller
        txn = state.current_transaction

        if txn
          txn.create_nested_frame(state, category, options)
        else
          txn = start_new_transaction(state, category, options)
        end

        txn
      rescue => e
        NewRelic::Agent.logger.error("Exception during Transaction.start", e)
        nil
      end

      def self.start_new_transaction(state, category, options)
        txn = Transaction.new(category, options)
        state.reset(txn)
        txn.start(state)
        txn
      end

      FAILED_TO_STOP_MESSAGE = "Failed during Transaction.stop because there is no current transaction"

      def self.stop(state, end_time=Time.now)
        txn = state.current_transaction

        if txn.nil?
          NewRelic::Agent.logger.error(FAILED_TO_STOP_MESSAGE)
          return
        end

        nested_frame = txn.frame_stack.pop

        if txn.frame_stack.empty?
          txn.stop(state, end_time, nested_frame)
          state.reset
        else
          nested_name = nested_transaction_name(nested_frame.name)

          if nested_name.start_with?(MIDDLEWARE_PREFIX)
            summary_metrics = MIDDLEWARE_SUMMARY_METRICS
          else
            summary_metrics = EMPTY_SUMMARY_METRICS
          end

          NewRelic::Agent::MethodTracerHelpers.trace_execution_scoped_footer(
            state,
            nested_frame.start_time.to_f,
            nested_name,
            summary_metrics,
            nested_frame,
            NESTED_TRACE_STOP_OPTIONS,
            end_time.to_f)
        end

        :transaction_stopped
      rescue => e
        state.reset
        NewRelic::Agent.logger.error("Exception during Transaction.stop", e)
        nil
      end

      def self.nested_transaction_name(name)
        if name.start_with?(CONTROLLER_PREFIX) || name.start_with?(OTHER_TRANSACTION_PREFIX)
          "#{SUBTRANSACTION_PREFIX}#{name}"
        else
          name
        end
      end

      # Indicate that you don't want to keep the currently saved transaction
      # information
      def self.abort_transaction! #THREAD_LOCAL_ACCESS
        state = NewRelic::Agent::TransactionState.tl_get
        txn = state.current_transaction
        txn.abort_transaction!(state) if txn
      end

      # See NewRelic::Agent.notice_error for options and commentary
      def self.notice_error(e, options={}) #THREAD_LOCAL_ACCESS
        state = NewRelic::Agent::TransactionState.tl_get
        txn = state.current_transaction
        if txn
          txn.notice_error(e, options)
        elsif NewRelic::Agent.instance
          NewRelic::Agent.instance.error_collector.notice_error(e, options)
        end
      end

      # Returns truthy if the current in-progress transaction is considered a
      # a web transaction (as opposed to, e.g., a background transaction).
      #
      # @api public
      #
      def self.recording_web_transaction? #THREAD_LOCAL_ACCESS
        txn = tl_current
        txn && txn.recording_web_transaction?
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

      def self.add_agent_attribute(key, value, default_destinations)
        if txn = tl_current
          txn.add_agent_attribute(key, value, default_destinations)
        else
          NewRelic::Agent.logger.debug "Attempted to add agent attribute: #{key} without transaction"
        end
      end

      def add_agent_attribute(key, value, default_destinations)
        @attributes.add_agent_attribute(key, value, default_destinations)
      end

      def self.merge_untrusted_agent_attributes(attributes, prefix, default_destinations)
        if txn = tl_current
          txn.merge_untrusted_agent_attributes(attributes, prefix, default_destinations)
        else
          NewRelic::Agent.logger.debug "Attempted to merge untrusted attributes without transaction"
        end
      end

      def merge_untrusted_agent_attributes(attributes, prefix, default_destinations)
        @attributes.merge_untrusted_agent_attributes(attributes, prefix, default_destinations)
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

      def initialize(category, options)
        @frame_stack = []
        @has_children = false

        self.default_name = options[:transaction_name]
        @overridden_name    = nil
        @frozen_name      = nil

        @category = category
        @start_time = Time.now
        @apdex_start = options[:apdex_start_time] || @start_time
        @jruby_cpu_start = jruby_cpu_time
        @process_cpu_start = process_cpu
        @gc_start_snapshot = NewRelic::Agent::StatsEngine::GCProfiler.take_snapshot
        @filtered_params = options[:filtered_params] || {}

        @exceptions = {}
        @metrics = TransactionMetrics.new
        @guid = generate_guid
        @cat_path_hashes = nil

        @ignore_this_transaction = false
        @ignore_apdex = false
        @ignore_enduser = false
        @ignore_trace = false

        @attributes = Attributes.new(NewRelic::Agent.instance.attribute_filter)

        merge_request_parameters(@filtered_params)

        if request = options[:request]
          @request_attributes = RequestAttributes.new request
        else
          @request_attributes = nil
        end
      end

      def referer
        @request_attributes && @request_attributes.referer
      end

      def request_path
        @request_attributes && @request_attributes.request_path
      end

      def request_port
        @request_attributes && @request_attributes.port
      end

      # This transaction-local hash may be used as temprory storage by
      # instrumentation that needs to pass data from one instrumentation point
      # to another.
      #
      # For example, if both A and B are instrumented, and A calls B
      # but some piece of state needed by the instrumentation at B is only
      # available at A, the instrumentation at A may write into the hash, call
      # through, and then remove the key afterwards, allowing the
      # instrumentation at B to read the value in between.
      #
      # Keys should be symbols, and care should be taken to not generate key
      # names dynamically, and to ensure that keys are removed upon return from
      # the method that creates them.
      #
      def instrumentation_state
        @instrumentation_state ||= {}
      end

      def overridden_name=(name)
        @overridden_name = Helper.correctly_encoded(name)
      end

      def default_name=(name)
        @default_name = Helper.correctly_encoded(name)
      end

      def create_nested_frame(state, category, options)
        @has_children = true
        if options[:filtered_params] && !options[:filtered_params].empty?
          @filtered_params = options[:filtered_params]
          merge_request_parameters(options[:filtered_params])
        end

        frame_stack.push NewRelic::Agent::MethodTracerHelpers.trace_execution_scoped_header(state, Time.now.to_f)
        name_last_frame(options[:transaction_name])

        set_default_transaction_name(options[:transaction_name], category)
      end

      def merge_request_parameters(params)
        merge_untrusted_agent_attributes(params, :'request.parameters', AttributeFilter::DST_NONE)
      end

      def make_transaction_name(name, category=nil)
        namer = Instrumentation::ControllerInstrumentation::TransactionNamer
        "#{namer.prefix_for_category(self, category)}#{name}"
      end

      def set_default_transaction_name(name, category)
        return log_frozen_name(name) if name_frozen?
        if influences_transaction_name?(category)
          self.default_name = name
          @category = category if category
        end
      end

      def set_overriding_transaction_name(name, category)
        return log_frozen_name(name) if name_frozen?
        if influences_transaction_name?(category)
          self.overridden_name = name
          @category = category if category
        end
      end

      def name_last_frame(name)
        frame_stack.last.name = name
      end

      def log_frozen_name(name)
        NewRelic::Agent.logger.warn("Attempted to rename transaction to '#{name}' after transaction name was already frozen as '#{@frozen_name}'.")
        nil
      end

      def influences_transaction_name?(category)
        !category || frame_stack.size == 1 || similar_category?(category)
      end

      def best_name
        @frozen_name  || @overridden_name ||
          @default_name || NewRelic::Agent::UNKNOWN_METRIC
      end

      def name_set?
        (@overridden_name || @default_name) ? true : false
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

      def start(state)
        return if !state.is_execution_traced?

        transaction_sampler.on_start_transaction(state, start_time)
        sql_sampler.on_start_transaction(state, start_time, request_path)
        NewRelic::Agent.instance.events.notify(:start_transaction)
        NewRelic::Agent::BusyCalculator.dispatcher_start(start_time)

        frame_stack.push NewRelic::Agent::MethodTracerHelpers.trace_execution_scoped_header(state, start_time.to_f)
        name_last_frame @default_name
      end

      # Call this to ensure that the current transaction trace is not saved
      # To fully ignore all metrics and errors, use ignore! instead.
      def abort_transaction!(state)
        @ignore_trace = true
      end

      WEB_SUMMARY_METRIC   = 'HttpDispatcher'.freeze
      OTHER_SUMMARY_METRIC = 'OtherTransaction/all'.freeze

      def summary_metrics
        if @frozen_name.start_with?(CONTROLLER_PREFIX)
          [WEB_SUMMARY_METRIC]
        else
          background_summary_metrics
        end
      end

      def background_summary_metrics
        segments = @frozen_name.split('/')
        if segments.size > 2
          ["OtherTransaction/#{segments[1]}/all", OTHER_SUMMARY_METRIC]
        else
          []
        end
      end

      def needs_middleware_summary_metrics?(name)
        name.start_with?(MIDDLEWARE_PREFIX)
      end

      def stop(state, end_time, outermost_frame)
        return if !state.is_execution_traced?
        freeze_name_and_execute_if_not_ignored
        ignore! if user_defined_rules_ignore?

        if @has_children
          name = Transaction.nested_transaction_name(outermost_frame.name)
          trace_options = TRACE_OPTIONS_SCOPED
        else
          name = @frozen_name
          trace_options = TRACE_OPTIONS_UNSCOPED
        end

        # These metrics are recorded here instead of in record_summary_metrics
        # in order to capture the exclusive time associated with the outer-most
        # TT node.
        if needs_middleware_summary_metrics?(name)
          summary_metrics_with_exclusive_time = MIDDLEWARE_SUMMARY_METRICS
        else
          summary_metrics_with_exclusive_time = EMPTY_SUMMARY_METRICS
        end

        NewRelic::Agent::MethodTracerHelpers.trace_execution_scoped_footer(
          state,
          start_time.to_f,
          name,
          summary_metrics_with_exclusive_time,
          outermost_frame,
          trace_options,
          end_time.to_f)

        NewRelic::Agent::BusyCalculator.dispatcher_finish(end_time)

        commit!(state, end_time, name) unless @ignore_this_transaction
      end

      def user_defined_rules_ignore?
        return unless request_path
        return if (rules = NewRelic::Agent.config[:"rules.ignore_url_regexes"]).empty?

        rules.any? do |rule|
          request_path.match(rule)
        end
      end

      def commit!(state, end_time, outermost_node_name)
        assign_agent_attributes
        assign_intrinsics(state)

        @transaction_trace = transaction_sampler.on_finishing_transaction(state, self, end_time)
        sql_sampler.on_finishing_transaction(state, @frozen_name)

        record_summary_metrics(outermost_node_name, end_time)
        record_apdex(state, end_time) unless ignore_apdex?
        record_queue_time

        generate_payload(state, start_time, end_time)

        record_exceptions
        record_transaction_event

        merge_metrics
        send_transaction_finished_event
      end

      def assign_agent_attributes
        default_destinations = AttributeFilter::DST_TRANSACTION_TRACER |
                               AttributeFilter::DST_TRANSACTION_EVENTS |
                               AttributeFilter::DST_ERROR_COLLECTOR

        if http_response_code
          add_agent_attribute(:httpResponseCode, http_response_code.to_s, default_destinations)
        end

        if response_content_length
          add_agent_attribute(:'response.headers.contentLength', response_content_length.to_i, default_destinations)
        end

        if response_content_type
          add_agent_attribute(:'response.headers.contentType', response_content_type, default_destinations)
        end

        if @request_attributes
          @request_attributes.assign_agent_attributes self
        end

        display_host = Agent.config[:'process_host.display_name']
        unless display_host == NewRelic::Agent::Hostname.get
          add_agent_attribute(:'host.displayName', display_host, default_destinations)
        end
      end

      def assign_intrinsics(state)
        if gc_time = calculate_gc_time
          attributes.add_intrinsic_attribute(:gc_time, gc_time)
        end

        if burn = cpu_burn
          attributes.add_intrinsic_attribute(:cpu_time, burn)
        end

        if is_synthetics_request?
          attributes.add_intrinsic_attribute(:synthetics_resource_id, synthetics_resource_id)
          attributes.add_intrinsic_attribute(:synthetics_job_id, synthetics_job_id)
          attributes.add_intrinsic_attribute(:synthetics_monitor_id, synthetics_monitor_id)
        end

        if state.is_cross_app?
          attributes.add_intrinsic_attribute(:trip_id, cat_trip_id(state))
          attributes.add_intrinsic_attribute(:path_hash, cat_path_hash(state))
        end
      end

      def calculate_gc_time
        gc_stop_snapshot = NewRelic::Agent::StatsEngine::GCProfiler.take_snapshot
        NewRelic::Agent::StatsEngine::GCProfiler.record_delta(gc_start_snapshot, gc_stop_snapshot)
      end

      # The summary metrics recorded by this method all end up with a duration
      # equal to the transaction itself, and an exclusive time of zero.
      def record_summary_metrics(outermost_node_name, end_time)
        metrics = summary_metrics
        metrics << @frozen_name unless @frozen_name == outermost_node_name
        @metrics.record_unscoped(metrics, end_time.to_f - start_time.to_f, 0)
      end

      # This event is fired when the transaction is fully completed. The metric
      # values and sampler can't be successfully modified from this event.
      def send_transaction_finished_event
        agent.events.notify(:transaction_finished, payload)
      end

      def generate_payload(state, start_time, end_time)
        duration = end_time.to_f - start_time.to_f
        @payload = {
          :name                 => @frozen_name,
          :bucket               => recording_web_transaction? ? :request : :background,
          :start_timestamp      => start_time.to_f,
          :duration             => duration,
          :metrics              => @metrics,
          :attributes           => @attributes,
          :error                => false
        }
        append_cat_info(state, duration, @payload)
        append_apdex_perf_zone(duration, @payload)
        append_synthetics_to(state, @payload)
        append_referring_transaction_guid_to(state, @payload)
      end

      def include_guid?(state, duration)
        state.is_cross_app? || is_synthetics_request?
      end

      def cat_trip_id(state)
        NewRelic::Agent.instance.cross_app_monitor.client_referring_transaction_trip_id(state) || guid
      end

      def cat_path_hash(state)
        referring_path_hash = cat_referring_path_hash(state) || '0'
        seed = referring_path_hash.to_i(16)
        result = NewRelic::Agent.instance.cross_app_monitor.path_hash(best_name, seed)
        record_cat_path_hash(result)
        result
      end

      def record_cat_path_hash(hash)
        @cat_path_hashes ||= []
        if @cat_path_hashes.size < 10 && !@cat_path_hashes.include?(hash)
          @cat_path_hashes << hash
        end
      end

      def cat_referring_path_hash(state)
        NewRelic::Agent.instance.cross_app_monitor.client_referring_transaction_path_hash(state)
      end

      def is_synthetics_request?
        synthetics_payload != nil && raw_synthetics_header != nil
      end

      def synthetics_version
        info = synthetics_payload or return nil
        info[0]
      end

      def synthetics_account_id
        info = synthetics_payload or return nil
        info[1]
      end

      def synthetics_resource_id
        info = synthetics_payload or return nil
        info[2]
      end

      def synthetics_job_id
        info = synthetics_payload or return nil
        info[3]
      end

      def synthetics_monitor_id
        info = synthetics_payload or return nil
        info[4]
      end

      APDEX_S = 'S'.freeze
      APDEX_T = 'T'.freeze
      APDEX_F = 'F'.freeze

      def append_apdex_perf_zone(duration, payload)
        if recording_web_transaction?
          bucket = apdex_bucket(duration, apdex_t)
        elsif background_apdex_t = transaction_specific_apdex_t
          bucket = apdex_bucket(duration, background_apdex_t)
        end

        return unless bucket

        bucket_str = case bucket
        when :apdex_s then APDEX_S
        when :apdex_t then APDEX_T
        when :apdex_f then APDEX_F
        else nil
        end
        payload[:apdex_perf_zone] = bucket_str if bucket_str
      end

      def append_cat_info(state, duration, payload)
        return unless include_guid?(state, duration)
        payload[:guid] = guid

        return unless state.is_cross_app?
        trip_id             = cat_trip_id(state)
        path_hash           = cat_path_hash(state)
        referring_path_hash = cat_referring_path_hash(state)

        payload[:cat_trip_id]             = trip_id             if trip_id
        payload[:cat_referring_path_hash] = referring_path_hash if referring_path_hash

        if path_hash
          payload[:cat_path_hash] = path_hash

          alternate_path_hashes = cat_path_hashes - [path_hash]
          unless alternate_path_hashes.empty?
            payload[:cat_alternate_path_hashes] = alternate_path_hashes
          end
        end
      end

      def append_synthetics_to(state, payload)
        return unless is_synthetics_request?

        payload[:synthetics_resource_id] = synthetics_resource_id
        payload[:synthetics_job_id]      = synthetics_job_id
        payload[:synthetics_monitor_id]  = synthetics_monitor_id
      end

      def append_referring_transaction_guid_to(state, payload)
        referring_guid = NewRelic::Agent.instance.cross_app_monitor.client_referring_transaction_guid(state)
        if referring_guid
          payload[:referring_transaction_guid] = referring_guid
        end
      end

      def merge_metrics
        NewRelic::Agent.instance.stats_engine.merge_transaction_metrics!(@metrics, best_name)
      end

      def record_exceptions
        error_recorded = false
        @exceptions.each do |exception, options|
          options[:uri]      ||= request_path if request_path
          options[:port]       = request_port if request_port
          options[:metric]     = best_name
          options[:attributes] = @attributes

          error_recorded = !!agent.error_collector.notice_error(exception, options) || error_recorded
        end
        payload[:error] = error_recorded if payload
      end

      # Do not call this.  Invoke the class method instead.
      def notice_error(error, options={}) # :nodoc:
        if @exceptions[error]
          @exceptions[error].merge! options
        else
          @exceptions[error] = options
        end
      end

      def record_transaction_event
        agent.transaction_event_recorder.record payload
      end

      QUEUE_TIME_METRIC = 'WebFrontend/QueueTime'.freeze

      def queue_time
        @apdex_start ? @start_time - @apdex_start : 0
      end

      def record_queue_time
        value = queue_time
        if value > 0.0
          if value < MethodTracerHelpers::MAX_ALLOWED_METRIC_DURATION
            @metrics.record_unscoped(QUEUE_TIME_METRIC, value)
          else
            ::NewRelic::Agent.logger.log_once(:warn, :too_high_queue_time, "Not recording unreasonably large queue time of #{value} s")
          end
        end
      end

      APDEX_ALL_METRIC   = 'ApdexAll'.freeze

      APDEX_METRIC       = 'Apdex'.freeze
      APDEX_OTHER_METRIC = 'ApdexOther'.freeze

      APDEX_TXN_METRIC_PREFIX       = 'Apdex/'.freeze
      APDEX_OTHER_TXN_METRIC_PREFIX = 'ApdexOther/Transaction/'.freeze

      def had_error?
        @exceptions.each do |exception, _|
          return true unless NewRelic::Agent.instance.error_collector.error_is_ignored?(exception)
        end
        false
      end

      def apdex_bucket(duration, current_apdex_t)
        self.class.apdex_bucket(duration, had_error?, current_apdex_t)
      end

      def record_apdex(state, end_time=Time.now)
        return unless state.is_execution_traced?

        freeze_name_and_execute_if_not_ignored do
          total_duration  = end_time - apdex_start
          action_duration = end_time - start_time

          if recording_web_transaction?
            record_apdex_metrics(APDEX_METRIC, APDEX_TXN_METRIC_PREFIX,
                                 total_duration, action_duration, apdex_t)
          else
            record_apdex_metrics(APDEX_OTHER_METRIC, APDEX_OTHER_TXN_METRIC_PREFIX,
                                 total_duration, action_duration, transaction_specific_apdex_t)
          end
        end
      end

      def record_apdex_metrics(rollup_metric, transaction_prefix, total_duration, action_duration, current_apdex_t)
        return unless current_apdex_t

        apdex_bucket_global = apdex_bucket(total_duration, current_apdex_t)
        apdex_bucket_txn    = apdex_bucket(action_duration, current_apdex_t)

        @metrics.record_unscoped(rollup_metric, apdex_bucket_global, current_apdex_t)
        @metrics.record_unscoped(APDEX_ALL_METRIC, apdex_bucket_global, current_apdex_t)
        txn_apdex_metric = @frozen_name.sub(/^[^\/]+\//, transaction_prefix)
        @metrics.record_unscoped(txn_apdex_metric, apdex_bucket_txn, current_apdex_t)
      end

      def apdex_t
        transaction_specific_apdex_t || Agent.config[:apdex_t]
      end

      def transaction_specific_apdex_t
        key = :web_transactions_apdex
        Agent.config[key] && Agent.config[key][best_name]
      end

      def with_database_metric_name(model, method, product=nil)
        previous = self.instrumentation_state[:datastore_override]
        model_name = case model
                     when Class
                       model.name
                     when String
                       model
                     else
                       model.to_s
                     end
        self.instrumentation_state[:datastore_override] = [method, model_name, product]
        yield
      ensure
        self.instrumentation_state[:datastore_override] = previous
      end

      def add_custom_attributes(p)
        attributes.merge_custom_attributes(p)
      end

      alias_method :set_user_attributes, :add_custom_attributes
      alias_method :add_custom_parameters, :add_custom_attributes

      def recording_web_transaction?
        web_category?(@category)
      end

      def web_category?(category)
        WEB_TRANSACTION_CATEGORIES.include?(category)
      end

      def similar_category?(category)
        web_category?(@category) == web_category?(category)
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

      def ignore_trace?
        @ignore_trace
      end

      private

      def process_cpu
        return nil if defined? JRuby
        p = Process.times
        p.stime + p.utime
      end

      JRUBY_CPU_TIME_ERROR = "Error calculating JRuby CPU Time".freeze
      def jruby_cpu_time
        return nil unless @@java_classes_loaded
        threadMBean = Java::JavaLangManagement::ManagementFactory.getThreadMXBean()

        return nil unless threadMBean.isCurrentThreadCpuTimeSupported
        java_utime = threadMBean.getCurrentThreadUserTime()  # ns

        -1 == java_utime ? 0.0 : java_utime/1e9
      rescue => e
        ::NewRelic::Agent.logger.log_once(:warn, :jruby_cpu_time, JRUBY_CPU_TIME_ERROR, e)
        ::NewRelic::Agent.logger.debug(JRUBY_CPU_TIME_ERROR, e)
        nil
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
