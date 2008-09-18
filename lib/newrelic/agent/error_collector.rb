require 'newrelic/agent/synchronize'
require 'newrelic/noticed_error'
require 'newrelic/agent/collection_helper'
require 'logger'

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
      @ignore = {}
      @ignore_filter = nil
      @capture_params = true
      @capture_source = false
      @enabled = true
    end
    
    
    def ignore_error_filter(&block)
      @ignore_filter = block
    end
    
    
    # errors is an array of String exceptions
    #
    def ignore(errors)
      errors.each { |error| @ignore[error] = true; log.debug("Ignoring error: '#{error}'") }
    end
   
    
    def notice_error(path, request_uri, params, exception)
      
      return if !@enabled || @ignore[exception.class.name] 
      
      if @ignore_filter
        exception = @ignore_filter.call(exception)
        
        return if exception.nil?
      end
      
      @@error_stat ||= NewRelic::Agent.get_stats("Errors/all")
      
      @@error_stat.increment_count
      
      data = {}
      
      data[:request_params] = normalize_params(params) if @capture_params
      data[:custom_params] = normalize_params(@agent.custom_params)
              
      data[:request_uri] = request_uri
            
      data[:rails_root] = RAILS_ROOT if defined? RAILS_ROOT
      
      data[:file_name] = exception.file_name if exception.respond_to?('file_name')
      data[:line_number] = exception.line_number if exception.respond_to?('line_number')
      
      if @capture_source && exception.respond_to?('source_extract')
        data[:source] = exception.source_extract
      end
      
      data[:stack_trace] = clean_exception(exception)
      noticed_error = NoticedError.new(path, data, exception)
      
      synchronize do
        if @errors.length >= MAX_ERROR_QUEUE_LENGTH
          log.info("Not reporting error (queue exceeded maximum length): #{exception.message}")
        else
          @errors << noticed_error
        end
      end
    end
    
    def harvest_errors(unsent_errors)
      synchronize do
        errors = (unsent_errors || []) + @errors
        @errors = []
        return errors
      end
    end
    
  private
    def log 
      return @agent.log if @agent && @agent.log
      
      @backup_log ||= Logger.new(STDERR)
    end
  end
end