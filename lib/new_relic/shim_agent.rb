require 'new_relic/stats'

# This agent is loaded by the plug when the plug-in is disabled
# It recreates just enough of the API to not break any clients that
# invoke the Agent


# from method_tracer.rb

class Module
  
  def trace_method_execution (*args)
    yield
  end
  
  def add_method_tracer (*args)
  end
  
  def remove_method_tracer(*args)
  end
  
end


# from agent.rb

module NewRelic
  module Agent
    
    class << self
      @@dummy_stats = NewRelic::MethodTraceStats.new
      def agent
        NewRelic::Agent::Agent.instance
      end
      
      alias instance agent
      
      def get_stats(*args)
        @@dummy_stats
      end
      def get_stats_no_scope(*args)
        @@dummy_stats
      end
      
      def manual_start(*args)
      end
      
      def set_sql_obfuscator(*args)
      end
      
      def disable_sql_recording
        yield
      end
      
      def disable_transaction_tracing
        yield
      end
      
      def add_request_parameters(*args)
      end
      def add_custom_parameters(*args)
      end
      def should_ignore_error
      end
    end  
    
    class Agent
      
      def initialize
        @error_collector = ErrorCollector.new
      end
      def self.instance
        @@agent ||= new
      end      
    end
    
    class ErrorCollector
      def notice_error(*args)
      end
    end
    
  end
end


module ActionController
  class Base
    def newrelic_notice_error(*args); end
    def self.newrelic_ignore(*args); end
    def new_relic_trace_controller_action(name); yield; end
    def newrelic_metric_path; end
    def perform_action_with_newrelic_trace(path=nil)
      yield
    end
  end
end if defined? ActionController::Base
