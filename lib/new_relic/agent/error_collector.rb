
module NewRelic
  module Agent
  class ErrorCollector
    include NewRelic::CollectionHelper

    # Defined the methods that need to be stubbed out when the
    # agent is disabled
    module Shim #:nodoc:
      def notice_error(*args); end
    end

    MAX_ERROR_QUEUE_LENGTH = 20 unless defined? MAX_ERROR_QUEUE_LENGTH

    attr_accessor :enabled
    attr_reader :config_enabled

    def initialize
      @errors = []
      # lookup of exception class names to ignore.  Hash for fast access
      @ignore = {}
      @ignore_filter = nil

      config = NewRelic::Control.instance.fetch('error_collector', {})

      @enabled = @config_enabled = config.fetch('enabled', true)
      @capture_source = config.fetch('capture_source', true)

      ignore_errors = config.fetch('ignore_errors', "")
      ignore_errors = ignore_errors.split(",") if ignore_errors.is_a? String
      ignore_errors.each { |error| error.strip! }
      ignore(ignore_errors)
      @lock = Mutex.new
    end

    def control
      NewRelic::Control.instance
    end

    def ignore_error_filter(&block)
      if block
        @ignore_filter = block
      else
        @ignore_filter
      end
    end

    # errors is an array of Exception Class Names
    #
    def ignore(errors)
      errors.each { |error| @ignore[error] = true; log.debug("Ignoring errors of type '#{error}'") }
    end

    module NoticeError
      def disabled?
        !@enabled
      end

      def filtered_by_error_filter?(error)
        return unless @ignore_filter
        !@ignore_filter.call(error)
      end

      def filtered_error?(error)
        @ignore[error.class.name] || filtered_by_error_filter?(error)
      end

      def error_is_ignored?(error)
        error && filtered_error?(error)
      end

      def increment_error_count!
        NewRelic::Agent.get_stats("Errors/all").increment_count
      end

      def should_exit_notice_error?(exception)
        if @enabled
          if !error_is_ignored?(exception)
            increment_error_count!
            return exception.nil?
          end
        end
        # disabled or an ignored error, per above
        true
      end

      def fetch_from_options(options, key, default=nil)
        options.delete(key) || default
      end

      def uri_ref_and_root(options)
        {
          :request_uri => fetch_from_options(options, :uri, ''),
          :request_referer => fetch_from_options(options, :referer, ''),
          :rails_root => control.root
        }
      end

      def custom_params_from_opts(options)
        # If anything else is left over, treat it like a custom param:        
        fetch_from_options(options, :custom_params, {}).merge(options)
      end

      def request_params_from_opts(options)
        value = options.delete(:request_params)
        if control.capture_params
          value
        else
          nil
        end
      end
      
      def normalized_request_and_custom_params(options)
        {
          :request_params => normalize_params(request_params_from_opts(options)),
          :custom_params  => normalize_params(custom_params_from_opts(options))
        }
      end
      
      def error_params_from_options(options)
        uri_ref_and_root(options).merge(normalized_request_and_custom_params(options))
      end

      def sense_method(object, method)
        object.send(method) if object.respond_to?(method)
      end

      def extract_source(exception)
        sense_method(exception, 'source_extract') if @capture_source
      end

      def extract_stack_trace(exception)
        actual_exception = sense_method(exception, 'original_exception') || exception
        sense_method(actual_exception, 'backtrace') || '<no stack trace>'
      end

      def exception_info(exception)
        {
          :file_name => sense_method(exception, 'file_name'),
          :line_number => sense_method(exception, 'line_number'),
          :source => extract_source(exception),
          :stack_trace => extract_stack_trace(exception)
        }
      end

      def over_queue_limit?(exception)
        over_limit = (@errors.length >= MAX_ERROR_QUEUE_LENGTH)
        log.warn("The error reporting queue has reached #{MAX_ERROR_QUEUE_LENGTH}. The error detail for this and subsequent errors will not be transmitted to RPM until the queued errors have been sent: #{exception}") if over_limit
        over_limit
      end
      

      def add_to_error_queue(noticed_error, exception)
        @lock.synchronize do
          @errors << noticed_error unless over_queue_limit?(exception)
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
    def notice_error(exception, options={})
      return if should_exit_notice_error?(exception)
      action_path     = fetch_from_options(options, :metric, (NewRelic::Agent.instance.stats_engine.scope_name || ''))
      exception_options = error_params_from_options(options).merge(exception_info(exception))
      add_to_error_queue(NewRelic::NoticedError.new(action_path, exception_options, exception), exception)
      exception
    rescue Exception => e
      log.error("Error capturing an error, yodawg. #{e}")
    end

    # Get the errors currently queued up.  Unsent errors are left
    # over from a previous unsuccessful attempt to send them to the server.
    # We first clear out all unsent errors before sending the newly queued errors.
    def harvest_errors(unsent_errors)
      if unsent_errors && !unsent_errors.empty?
        return unsent_errors
      else
        @lock.synchronize do
          errors = @errors
          @errors = []
          return errors
        end
      end
    end

    private
    def log
      NewRelic::Agent.logger
    end
  end
end
end
