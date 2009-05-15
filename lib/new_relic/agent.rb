# = New Relic Agent
#
# New Relic RPM is a performance monitoring application for Ruby applications running
# in production.  For more information on RPM please visit http://www.newrelic.com.
#
# The New Relic Agent can be installed in Ruby applications to gather runtime performance
# metrics, traces, and errors for display in a Developer Mode UI (mapped to /newrelic in your application 
# server) or for monitoring and analysis at http://rpm.newrelic.com.
#
# For detailed information on configuring or customizing the RPM Agent please visit our
# {support and documentation site}[http://support.newrelic.com].
#
# == Starting the Agent as a Gem
#
# For Rails, add:
#    config.gem 'newrelic_rpm'
# to your initialization sequence.
#
# For merb, do 
#    dependency 'newrelic_rpm'
# in the Merb config/init.rb
#
# For other frameworks, or to manage the agent manually, invoke NewRelic::Agent#manual_start
# directly.
#
# == Configuring the Agent
# 
# All agent configuration is done in the +newrelic.yml+ file.  This file is by
# default read from the +config+ directory of the application root and is subsequently
# searched for in the application root directory, and then in a +~/.newrelic+ directory
#
# == Agent APIs
#
# The agent has some APIs available for extending and customizing.
#
# :main: new_relic/agent.rb
module NewRelic

  # Methods in the Agent module are delegated to the NewRelic::Agent::Agent
  # singleton instance.
  module Agent
    extend self
    
    require 'new_relic/version'
    require 'new_relic/local_environment'
    require 'new_relic/stats'
    require 'new_relic/metric_spec'
    require 'new_relic/metric_data'
    require 'new_relic/metric_parser'
    require 'new_relic/transaction_analysis'
    require 'new_relic/transaction_sample'
    require 'new_relic/noticed_error'
    
    require 'new_relic/agent/chained_call'
    require 'new_relic/agent/agent'
    require 'new_relic/agent/shim_agent'
    require 'new_relic/agent/method_tracer'
    require 'new_relic/agent/worker_loop'
    require 'new_relic/agent/stats_engine'
    require 'new_relic/agent/collection_helper'
    require 'new_relic/agent/transaction_sampler'
    require 'new_relic/agent/error_collector'
    require 'new_relic/agent/sampler'
    
    require 'new_relic/agent/samplers/cpu_sampler'
    require 'new_relic/agent/samplers/memory_sampler'
    require 'new_relic/agent/samplers/mongrel_sampler'
    require 'set'
    require 'sync'
    require 'thread'
    require 'resolv'
    require 'timeout'
    
    # An exception that is thrown by the server if the agent license is invalid.
    class LicenseException < StandardError; end
    
    # An exception that forces an agent to stop reporting until its mongrel is restarted.
    class ForceDisconnectException < StandardError; end
    
    # Used to blow out of a periodic task without logging a an error, such as for routine
    # failures.
    class IgnoreSilentlyException < StandardError; end
    
    # Reserved for future use.  Meant to represent a problem on the server side.
    class ServerError < StandardError; end

    class BackgroundLoadingError < StandardError; end
    
    @@agent = nil

    # The singleton Agent instance.
    def agent
      raise "Plugin not initialized!" if @@agent.nil?
      @@agent
    end
    
    def agent= new_instance
      @@agent = new_instance
    end
    
    alias instance agent

    # Get or create a statistics gatherer that will aggregate numerical data
    # under a metric name.
    #
    # +metric_name+ should follow a slash separated path convention.  Application
    # specific metrics should begin with "Custom/".
    #
    # Return a NewRelic::Stats that accepts data
    # via calls to add_data_point(value).
    def get_stats(metric_name, use_scope=false)
      @@agent.stats_engine.get_stats(metric_name, use_scope)
    end
    
    def get_stats_no_scope(metric_name)
      @@agent.stats_engine.get_stats_no_scope(metric_name)
    end
    
    # Call this to manually start the Agent in situations where the Agent does
    # not auto-start.
    # 
    # When the app environment loads, so does the Agent. However, the Agent will
    # only connect to RPM if a web front-end is found. If you want to selectively monitor
    # ruby processes that don't use web plugins, then call this method in your
    # code and the Agent will fire up and start reporting to RPM.
    #
    # All arguments ignored except options like +:app_name = XXXX+ option which 
    # will override the settings in the newrelic_yml.
    #
    def manual_start(options={})
      raise unless Hash === options
      # Ignore all args but hash options
      options.merge! :agent_enabled => true 
      NewRelic::Control.instance.init_plugin options
    end

    # This method sets the block sent to this method as a sql obfuscator. 
    # The block will be called with a single String SQL statement to obfuscate.
    # The method must return the obfuscated String SQL. 
    # If chaining of obfuscators is required, use type = :before or :after
    #
    # type = :before, :replace, :after
    #
    # Example:
    #
    #    NewRelic::Agent.set_sql_obfuscator(:replace) do |sql|
    #       my_obfuscator(sql)
    #    end
    # 
    def set_sql_obfuscator(type = :replace, &block)
      agent.set_sql_obfuscator type, &block
    end
    
    
    # This method sets the state of sql recording in the transaction
    # sampler feature. Within the given block, no sql will be recorded
    #
    # usage:
    #
    #   NewRelic::Agent.disable_sql_recording do
    #     ...  
    #   end
    #     
    def disable_sql_recording
      state = agent.set_record_sql(false)
      begin
        yield
      ensure
        agent.set_record_sql(state)
      end
    end
    
    # This method disables the recording of transaction traces in the given
    # block.
    def disable_transaction_tracing
      state = agent.set_record_tt(false)
      begin
        yield
      ensure
        agent.set_record_tt(state)
      end
    end
    
    # This method allows a filter to be applied to errors that RPM will track.
    # The block should return the exception to track (which could be different from
    # the original exception) or nil to ignore this exception
    #
    def ignore_error_filter(&block)
      agent.error_collector.ignore_error_filter(&block)
    end
    
    # Add parameters to the current transaction trace
    #
    def add_custom_parameters(params)
      agent.add_custom_parameters(params)
    end
    
    alias add_request_parameters add_custom_parameters

  end 
end  