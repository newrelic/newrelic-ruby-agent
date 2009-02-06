
module NewRelic::Agent
  class ErrorCollector
    include Synchronize
    include CollectionHelper
    
    MAX_ERROR_QUEUE_LENGTH = 20 unless defined? MAX_ERROR_QUEUE_LENGTH
    
    attr_accessor :capture_params
    attr_accessor :capture_source
    attr_accessor :enabled
    
    def initialize(agent = nil)
      @agent = agent
      @errors = []
      # lookup of exception class names to ignore.  Hash for fast access
      @ignore = {}
      @ignore_filter = nil
      @capture_params = true
      @capture_source = false
      @enabled = true
    end
    
    def ignore_error_filter(&block)
      @ignore_filter = block
    end
    
    
    # errors is an array of Exception Class Names
    #
    def ignore(errors)
      errors.each { |error| @ignore[error] = true; log.debug("Ignoring error: '#{error}'") }
    end
    
    
    def notice_error(path, request_uri, params, exception)
      
      return unless @enabled
      return if @ignore[exception.class.name] 
      
      if @ignore_filter
        exception = @ignore_filter.call(exception)
        
        return if exception.nil?
      end
      
      error_stat.increment_count
      
      data = {}
      
      data[:request_params] = normalize_params(params) if @capture_params
      data[:custom_params] = normalize_params(@agent.custom_params) if @agent
      
      data[:request_uri] = request_uri
      
      data[:rails_root] = NewRelic::Config.instance.root
      
      data[:file_name] = exception.file_name if exception.respond_to?('file_name')
      data[:line_number] = exception.line_number if exception.respond_to?('line_number')
      
      if @capture_source && exception.respond_to?('source_extract')
        data[:source] = exception.source_extract
      end
      
      if exception.respond_to? 'original_exception'
        inside_exception = exception.original_exception
      else
        inside_exception = exception
      end
      data[:stack_trace] = strip_nr_from_backtrace(inside_exception.backtrace)
      noticed_error = NewRelic::NoticedError.new(path, data, exception)
      
      synchronize do
        if @errors.length >= MAX_ERROR_QUEUE_LENGTH
          log.info("The error reporting queue has reached #{MAX_ERROR_QUEUE_LENGTH}. This error will not be reported to RPM: #{exception.message}")
        else
          @errors << noticed_error
        end
      end
    end
    
    # Get the errors currently queued up.  Unsent errors are left 
    # over from a previous unsuccessful attempt to send them to the server.
    # We first clear out all unsent errors before sending the newly queued errors.
    def harvest_errors(unsent_errors)
      if unsent_errors && !unsent_errors.empty?
        return unsent_errors
      else
        synchronize do
          errors = @errors
          @errors = []
          return errors
        end
      end
    end
    
    private
    def error_stat
      @error_stat ||= NewRelic::Agent.get_stats("Errors/all")
    end
    def log
      NewRelic::Config.instance.log
    end
  end
end