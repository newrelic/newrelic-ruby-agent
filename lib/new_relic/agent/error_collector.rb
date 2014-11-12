# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    # This class collects errors from the parent application, storing
    # them until they are harvested and transmitted to the server
    class ErrorCollector
      include NewRelic::CollectionHelper

      # Defined the methods that need to be stubbed out when the
      # agent is disabled
      module Shim #:nodoc:
        def notice_error(*args); end
      end

      # Maximum possible length of the queue - defaults to 20, may be
      # made configurable in the future. This is a tradeoff between
      # memory and data retention
      MAX_ERROR_QUEUE_LENGTH = 20 unless defined? MAX_ERROR_QUEUE_LENGTH

      attr_accessor :errors

      # Returns a new error collector
      def initialize
        @errors = []

        # lookup of exception class names to ignore.  Hash for fast access
        @ignore = {}

        initialize_ignored_errors(Agent.config[:'error_collector.ignore_errors'])
        @lock = Mutex.new

        Agent.config.register_callback(:'error_collector.enabled') do |config_enabled|
          ::NewRelic::Agent.logger.debug "Errors will #{config_enabled ? '' : 'not '}be sent to the New Relic service."
        end
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
        Agent.config[:'error_collector.enabled']
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
          undef :ignore_filter_proc
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

      # This module was extracted from the notice_error method - it is
      # internally tested and can be refactored without major issues.
      module NoticeError
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

        def seen?(txn, exception)
          error_ids = txn.nil? ? [] : txn.noticed_error_ids
          error_ids.include?(exception.object_id)
        end

        def tag_as_seen(state, exception)
          txn = state.current_transaction
          txn.noticed_error_ids << exception.object_id if txn
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

        def skip_notice_error?(state, exception)
          disabled? ||
            error_is_ignored?(exception) ||
            exception.nil? ||
            seen?(state.current_transaction, exception)
        end

        # acts just like Hash#fetch, but deletes the key from the hash
        def fetch_from_options(options, key, default=nil)
          options.delete(key) || default
        end

        # returns some basic option defaults pulled from the provided
        # options hash
        def uri_ref_and_root(options)
          {
            :request_uri => fetch_from_options(options, :uri, ''),
            :request_referer => fetch_from_options(options, :referer, ''),
            :rails_root => NewRelic::Control.instance.root
          }
        end

        # If anything else is left over, we treat it like a custom param
        def custom_params_from_opts(options)
          # If anything else is left over, treat it like a custom param:
          if Agent.config[:'error_collector.capture_attributes']
            fetch_from_options(options, :custom_params, {}).merge(options)
          else
            {}
          end
        end

        # takes the request parameters out of the options hash, and
        # returns them if we are capturing parameters, otherwise
        # returns nil
        def request_params_from_opts(options)
          value = options.delete(:request_params)
          if Agent.config[:capture_params]
            value
          else
            nil
          end
        end

        # normalizes the request and custom parameters before attaching
        # them to the error. See NewRelic::CollectionHelper#normalize_params
        def normalized_request_and_custom_params(options)
          {
            :request_params => normalize_params(request_params_from_opts(options)),
            :custom_params  => normalize_params(custom_params_from_opts(options))
          }
        end

        # Merges together many of the options into something that can
        # actually be attached to the error
        def error_params_from_options(options)
          uri_ref_and_root(options).merge(normalized_request_and_custom_params(options))
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

        # extracts a bunch of information from the exception to include
        # in the noticed error - some may or may not be available, but
        # we try to include all of it
        def exception_info(exception)
          {
            :file_name => sense_method(exception, 'file_name'),
            :line_number => sense_method(exception, 'line_number'),
            :stack_trace => extract_stack_trace(exception)
          }
        end

        # checks the size of the error queue to make sure we are under
        # the maximum limit, and logs a warning if we are over the limit.
        def over_queue_limit?(message)
          over_limit = (@errors.reject{|err| err.is_internal}.length >= MAX_ERROR_QUEUE_LENGTH)
          ::NewRelic::Agent.logger.warn("The error reporting queue has reached #{MAX_ERROR_QUEUE_LENGTH}. The error detail for this and subsequent errors will not be transmitted to New Relic until the queued errors have been sent: #{message}") if over_limit
          over_limit
        end

        # Synchronizes adding an error to the error queue, and checks if
        # the error queue is too long - if so, we drop the error on the
        # floor after logging a warning.
        def add_to_error_queue(noticed_error)
          @lock.synchronize do
            if !over_queue_limit?(noticed_error.message) && !@errors.include?(noticed_error)
              @errors << noticed_error
            end
          end
        end
      end

      include NoticeError


      # Notice the error with the given available options:
      #
      # * <tt>:uri</tt> => The request path, minus any request params or query string.
      # * <tt>:referer</tt> => The URI of the referer
      # * <tt>:metric</tt> => The metric name associated with the transaction
      # * <tt>:request_params</tt> => Request parameters, already filtered if necessary
      # * <tt>:custom_params</tt> => Custom parameters
      #
      # If anything is left over, it's added to custom params
      # If exception is nil, the error count is bumped and no traced error is recorded
      def notice_error(exception, options={}) #THREAD_LOCAL_ACCESS
        state = ::NewRelic::Agent::TransactionState.tl_get

        return if skip_notice_error?(state, exception)
        tag_as_seen(state, exception)

        increment_error_count!(state, exception, options)
        NewRelic::Agent.instance.events.notify(:notice_error, exception, options)

        action_path       = fetch_from_options(options, :metric, "")
        exception_options = error_params_from_options(options).merge(exception_info(exception))
        add_to_error_queue(NewRelic::NoticedError.new(action_path, exception_options, exception))

        exception
      rescue => e
        ::NewRelic::Agent.logger.warn("Failure when capturing error '#{exception}':", e)
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
        return unless exception.class < NewRelic::Agent::InternalAgentError

        # Log 'em all!
        NewRelic::Agent.logger.info(exception)

        @lock.synchronize do
          # Already seen this class once? Bail!
          return if @errors.any? { |err| err.exception_class_name == exception.class.name }

          trace = exception.backtrace || caller.dup
          noticed_error = NewRelic::NoticedError.new("NewRelic/AgentError",
                                                     {:stack_trace => trace},
                                                     exception)
          @errors << noticed_error
        end
      rescue => e
        NewRelic::Agent.logger.info("Unable to capture internal agent error due to an exception:", e)
      end

      def merge!(errors)
        errors.each do |error|
          add_to_error_queue(error)
        end
      end

      # Get the errors currently queued up.  Unsent errors are left
      # over from a previous unsuccessful attempt to send them to the server.
      def harvest!
        @lock.synchronize do
          errors = @errors
          @errors = []
          errors
        end
      end

      def reset!
        @lock.synchronize do
          @errors = []
        end
      end
    end
  end
end
