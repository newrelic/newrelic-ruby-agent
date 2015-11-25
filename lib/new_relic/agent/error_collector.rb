# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require 'new_relic/agent/error_trace_aggregator'
require 'new_relic/agent/error_event_aggregator'

module NewRelic
  module Agent
    # This class collects errors from the parent application, storing
    # them until they are harvested and transmitted to the server
    class ErrorCollector
      include NewRelic::CollectionHelper

      # Maximum possible length of the queue - defaults to 20, may be
      # made configurable in the future. This is a tradeoff between
      # memory and data retention
      MAX_ERROR_QUEUE_LENGTH = 20 unless defined? MAX_ERROR_QUEUE_LENGTH
      EXCEPTION_TAG_IVAR = :'@__nr_seen_exception' unless defined? EXCEPTION_TAG_IVAR

      attr_reader :error_trace_aggregator, :error_event_aggregator

      # Returns a new error collector
      def initialize
        @error_trace_aggregator = ErrorTraceAggregator.new(MAX_ERROR_QUEUE_LENGTH)
        @error_event_aggregator = ErrorEventAggregator.new

        # lookup of exception class names to ignore.  Hash for fast access
        @ignore = {}

        initialize_ignored_errors(Agent.config[:'error_collector.ignore_errors'])

        Agent.config.register_callback(:'error_collector.ignore_errors') do |ignore_errors|
          initialize_ignored_errors(ignore_errors)
        end
      end


      def initialize_ignored_errors(ignore_errors)
        @ignore.clear
        ignore_errors = ignore_errors.split(",") if ignore_errors.is_a? String
        ignore_errors.each { |error| error.strip! }
        ignore(ignore_errors)
      end

      def enabled?
        error_trace_aggregator.enabled? || error_event_aggregator.enabled?
      end

      def disabled?
        !enabled?
      end

      # We store the passed block in both an ivar on the class, and implicitly
      # within the body of the ignore_filter_proc method intentionally here.
      # The define_method trick is needed to get around the fact that users may
      # call 'return' from within their filter blocks, which would otherwise
      # result in a LocalJumpError.
      #
      # The raw block is also stored in an instance variable so that we can
      # return it later in its original form.
      #
      # This is all done at the class level in order to avoid the case where
      # the user sets up an ignore filter on one instance of the ErrorCollector,
      # and then that instance subsequently gets discarded during agent startup.
      # (For example, if the agent is initially disabled, and then gets enabled
      # via a call to manual_start later on.)
      #
      def self.ignore_error_filter=(block)
        @ignore_filter = block
        if block
          define_method(:ignore_filter_proc, &block)
        elsif method_defined?(:ignore_filter_proc)
          remove_method :ignore_filter_proc
        end
        @ignore_filter
      end

      def self.ignore_error_filter
        @ignore_filter
      end

      # errors is an array of Exception Class Names
      #
      def ignore(errors)
        errors.each do |error|
          @ignore[error] = true
          ::NewRelic::Agent.logger.debug("Ignoring errors of type '#{error}'")
        end
      end

      # Checks the provided error against the error filter, if there
      # is an error filter
      def filtered_by_error_filter?(error)
        respond_to?(:ignore_filter_proc) && !ignore_filter_proc(error)
      end

      # Checks the array of error names and the error filter against
      # the provided error
      def filtered_error?(error)
        @ignore[error.class.name] || filtered_by_error_filter?(error)
      end

      # an error is ignored if it is nil or if it is filtered
      def error_is_ignored?(error)
        error && filtered_error?(error)
      rescue => e
        NewRelic::Agent.logger.error("Error '#{error}' will NOT be ignored. Exception '#{e}' while determining whether to ignore or not.", e)
        false
      end

      # Calling instance_variable_set on a wrapped Java object in JRuby will
      # generate a warning unless that object's class has already been marked
      # as persistent, so we skip tagging of exception objects that are actually
      # wrapped Java objects on JRuby.
      #
      # See https://github.com/jruby/jruby/wiki/Persistence
      #
      def exception_is_java_object?(exception)
        NewRelic::LanguageSupport.jruby? && exception.respond_to?(:java_class)
      end

      def exception_tagged?(exception)
        return false if exception_is_java_object?(exception)
        exception.instance_variable_defined?(EXCEPTION_TAG_IVAR)
      end

      def tag_exception(exception)
        return if exception_is_java_object?(exception)
        return if exception.frozen?
        begin
          exception.instance_variable_set(EXCEPTION_TAG_IVAR, true)
        rescue => e
          NewRelic::Agent.logger.warn("Failed to tag exception: #{exception}: ", e)
        end
      end

      def blamed_metric_name(txn, options)
        if options[:metric] && options[:metric] != ::NewRelic::Agent::UNKNOWN_METRIC
          "Errors/#{options[:metric]}"
        else
          "Errors/#{txn.best_name}" if txn
        end
      end

      def aggregated_metric_names(txn)
        metric_names = ["Errors/all"]
        return metric_names unless txn

        if txn.recording_web_transaction?
          metric_names << "Errors/allWeb"
        else
          metric_names << "Errors/allOther"
        end

        metric_names
      end

      # Increments a statistic that tracks total error rate
      def increment_error_count!(state, exception, options={})
        txn = state.current_transaction

        metric_names  = aggregated_metric_names(txn)
        blamed_metric = blamed_metric_name(txn, options)
        metric_names << blamed_metric if blamed_metric

        stats_engine = NewRelic::Agent.agent.stats_engine
        stats_engine.record_unscoped_metrics(state, metric_names) do |stats|
          stats.increment_count
        end
      end

      def skip_notice_error?(exception)
        disabled? ||
          error_is_ignored?(exception) ||
          exception.nil? ||
          exception_tagged?(exception)
      end

      # calls a method on an object, if it responds to it - used for
      # detection and soft fail-safe. Returns nil if the method does
      # not exist
      def sense_method(object, method)
        object.send(method) if object.respond_to?(method)
      end

      # extracts a stack trace from the exception for debugging purposes
      def extract_stack_trace(exception)
        actual_exception = sense_method(exception, 'original_exception') || exception
        sense_method(actual_exception, 'backtrace') || '<no stack trace>'
      end

      # See NewRelic::Agent.notice_error for options and commentary
      def notice_error(exception, options={}) #THREAD_LOCAL_ACCESS
        return if skip_notice_error?(exception)

        tag_exception(exception)

        state = ::NewRelic::Agent::TransactionState.tl_get
        increment_error_count!(state, exception, options)
        noticed_error = create_noticed_error(exception, options)
        error_trace_aggregator.add_to_error_queue(noticed_error)
        payload = state.current_transaction ? state.current_transaction.payload : nil
        error_event_aggregator.append_event(noticed_error, payload)
        exception
      rescue => e
        ::NewRelic::Agent.logger.warn("Failure when capturing error '#{exception}':", e)
        nil
      end

      EMPTY_STRING = ''.freeze

      def create_noticed_error(exception, options)
        error_metric = options.delete(:metric) || EMPTY_STRING

        noticed_error = NewRelic::NoticedError.new(error_metric, exception)
        noticed_error.request_uri = options.delete(:uri) || EMPTY_STRING
        noticed_error.request_port = options.delete(:port)
        noticed_error.attributes  = options.delete(:attributes)

        noticed_error.file_name   = sense_method(exception, :file_name)
        noticed_error.line_number = sense_method(exception, :line_number)
        noticed_error.stack_trace = extract_stack_trace(exception)

        handle_deprecated_options(options)

        noticed_error.attributes_from_notice_error = options.delete(:custom_params) || {}

        # Any options that are passed to notice_error which aren't known keys
        # get treated as custom attributes, so merge them into that hash.
        noticed_error.attributes_from_notice_error.merge!(options)

        noticed_error
      end

      DEPRECATED_OPTIONS_MSG = "Passing %s to notice_error is no longer supported. Set values on the enclosing transaction or record them as custom attributes instead.".freeze
      DEPRECATED_OPTIONS = [:request_params, :request, :referer].freeze

      # Old options no longer used by notice_error can still be passed. If they
      # are, they shouldn't get merged into custom attributes. Delete and
      # warn callers so they can fix their calls to notice_error.
      def handle_deprecated_options(options)
        DEPRECATED_OPTIONS.each do |deprecated|
          if options.include?(deprecated)
            NewRelic::Agent.logger.warn(DEPRECATED_OPTIONS_MSG % deprecated)
            options.delete(deprecated)
          end
        end
      end

      # *Use sparingly for difficult to track bugs.*
      #
      # Track internal agent errors for communication back to New Relic.
      # To use, make a specific subclass of NewRelic::Agent::InternalAgentError,
      # then pass an instance of it to this method when your problem occurs.
      #
      # Limits are treated differently for these errors. We only gather one per
      # class per harvest, disregarding (and not impacting) the app error queue
      # limit.
      def notice_agent_error(exception)
        @error_trace_aggregator.notice_agent_error(exception)
      end

      def drop_buffered_data
        @error_trace_aggregator.reset!
        @error_event_aggregator.reset!
        nil
      end
    end
  end
end
