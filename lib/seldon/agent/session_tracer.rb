require 'set'
require 'thread'

# The session tracer captures http requests from a session
module Seldon::Agent
  class TracedRequest
    def initialize(request, start_time)
      @uri = request.request_uri
      @timestamp = Time.now - start_time
      @params = request.cgi.params
      @active_record_writes = Set.new
      
      p @params
      puts "#{@timestamp}: #{@uri}"
    end
    
    def notice_database_write(active_record_class)
      @active_record_writes << active_record_class 
      puts "Write to #{active_record_class} for #{@uri}"
    end
  end
  
  class SessionTracer
    # the timeout specifies the maximum length in seconds for a 
    # traced session.
    TIMEOUT = 5 * 60
    
    attr_reader :closed
    
    def initialize
      @start_time = Time.now
      @history = []
      @closed = false
      
      puts "NEW SESSION CAPTURE"
    end
    
    def << (request)
      mutex.synchronize do
        Thread::current[:traced_request] = nil
        if Time.now - @start_time > TIMEOUT
          do_close  
        end
  
        unless closed
           tr = TracedRequest.new(request, @start_time) 
           @history << tr
           Thread::current[:traced_request] = tr
         end
       end
    end
    
    # stop tracing this session
    def close
      mutex.synchronize do
        do_close
      end
    end
    
  private
    def mutex
      @mutex ||= Mutex.new
    end
    
    def do_close
      return if closed
#      Seldon::Agent.instance.send_traced_session(self)
      @history = []
      @closed = true
    end
    
    class << self
      def notice_database_write(active_record_class)
        tr = Thread::current[:traced_request]
        tr.notice_database_write(active_record_class) if tr
      end
    end
  end
end

# add session tracing to http requests when a request comes in with
# a special paramer 'capture_session' set to true.
module ActionController #:nodoc:
  class Base
    def log_processing_with_capture_session
      trace_request
      
      # pass through to the underlying implementation
      log_processing_without_capture_session
    end
    
    alias_method_chain :log_processing, :capture_session
    
  private
    def trace_request
      # turn on tracing for this session if specified in the params
      if params[:capture_session] == 'start'
        session[:session_tracer] = Seldon::Agent::SessionTracer.new

      # turn off tracing for this session if specified in the params
      elsif params[:capture_session] == 'stop'
        tracer = session[:session_tracer]
        tracer.close if tracer
        session.remove[:session_tracer]
      end

      # trace this request if tracing is turned on for this session
      if session[:session_tracer]
        tracer = session[:session_tracer]
        tracer << request
      end
    end
  end
end

# patch ActiveRecord writes so we notice which http requests write to
# the database.  This is interesting for production monitoring since
# many customers won't want monitoring transactions that write to the db
# TODO this may be patent worthy
module ActiveRecord
  class Base
    def create_or_update_with_notice_write
      Seldon::Agent::SessionTracer.notice_database_write(self.class.name)
      create_or_update_without_notice_write
    end
    
    alias_method_chain :create_or_update, :notice_write
  end
end

