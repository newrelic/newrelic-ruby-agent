# NewRelic instrumentation for controllers
#
# This instrumentation is applied to the action controller by default if the agent
# is actively collecting statistics.  It will collect statistics for the 
# given action.
#
# In cases where you don't want to instrument the top level action, but instead
# have other methods which are dispatched to by your action, and you want to treat
# these as distinct actions, then what you need to do is call newrelic_ignore
# on the top level action, and manually instrument the called 'actions'.  
#
# Here's an example of a controller with a send_message action which dispatches
# to more specific send_servicename methods.  This results in the controller 
# action stats showing up for send_servicename.
#
# MyController < ActionController::Base
#   newrelic_ignore :only => 'send_message'
#   # dispatch this action to the method given by the service parameter.
#   def send_message
#     service = params['service']
#     dispatch_to_method = "send_messge_to_#{service}"
#     perform_action_with_newrelic_trace(dispatch_to_method) do
#       send dispatch_to_method, params['message']
#     end
#   end
# end

module NewRelic::Agent::Instrumentation
  module ControllerInstrumentation
    
    def self.included(clazz)
      clazz.extend(ClassMethods)
    end
    
    # This module is for importing stubs when the agent is disabled
    module ClassMethodsShim
      def newrelic_ignore(*args); end
    end
    
    module Shim
      def self.included(clazz)
        clazz.extend(ClassMethodsShim)
      end
      def newrelic_notice_error(*args); end
      def new_relic_trace_controller_action(*args); yield; end
      def newrelic_metric_path; end
      def perform_action_with_newrelic_trace(*args); yield; end
    end
    
    module ClassMethods
      # Have NewRelic ignore actions in this controller.  Specify the actions as hash options
      # using :except and :only.  If no actions are specified, all actions are ignored.
      def newrelic_ignore(specifiers={})
        if specifiers.empty?
          self.newrelic_ignore_attr = true
        elsif ! (Hash === specifiers)
          logger.error "newrelic_ignore takes an optional hash with :only and :except lists of actions (illegal argument type '#{specifiers.class}')"
        else
          self.newrelic_ignore_attr = specifiers
        end
      end
      # Should be implemented in the controller class via the inheritable attribute mechanism.
      def newrelic_ignore_attr=(value); end
      def newrelic_ignore_attr; end
    end
    
    # Must be implemented in the controller class:
    # Determine the path that is used in the metric name for
    # the called controller action.  Of the form controller_path/action_name
    # 
    def newrelic_metric_path(action_name_override = nil)
      raise "Not implemented!"
    end
    
    
    
    # Perform the current action with NewRelic tracing.  Used in a method
    # chain via aliasing.  Call directly if you want to instrument a specifc
    # block as if it were an action.  Pass the block along with the path.
    # The metric is named according to the action name, or the given path if called
    # directly.  
    def perform_action_with_newrelic_trace(*args)
      agent = NewRelic::Agent.instance
      stats_engine = agent.stats_engine
      
      ignore_actions = self.class.newrelic_ignore_attr
      # Skip instrumentation based on the value of 'do_not_trace' and if 
      # we aren't calling directly with a block.
      should_skip = !block_given? && case ignore_actions
        when nil; false
        when Hash
        only_actions = Array(ignore_actions[:only])
        except_actions = Array(ignore_actions[:except])
        only_actions.include?(action_name.to_sym) || (except_actions.any? && !except_actions.include?(action_name.to_sym))
      else
        true
      end
      
      if should_skip
        # Tell the dispatcher instrumentation that we ignored this action and it shouldn't
        # be counted for the overall HTTP operations measurement.
        Thread.current[:controller_ignored] = true
        
        return perform_action_without_newrelic_trace(*args)
      end

      # reset this in case we came through a code path where the top level controller is ignored
      Thread.current[:controller_ignored] = nil
      
      start = Time.now.to_f
      agent.ensure_worker_thread_started
      
      # generate metrics for all all controllers (no scope)
      self.class.trace_method_execution_no_scope "Controller" do 
        # assuming the first argument, if present, is the action name
        path = newrelic_metric_path(args.size > 0 ? args[0] : nil)
        controller_metric = "Controller/#{path}"
        
        self.class.trace_method_execution_with_scope controller_metric, true, true do 
          stats_engine.transaction_name = controller_metric
          
          local_params = (respond_to? :filter_parameters) ? filter_parameters(params) : params
          
          agent.transaction_sampler.notice_transaction(path, request, local_params)
          
          t = Process.times.utime + Process.times.stime
          
          failed = false
          
          begin
            # run the action
            if block_given?
              yield
            else
              perform_action_without_newrelic_trace(*args)
            end
          rescue Exception => e
            failed = true
            raise e
          ensure
            cpu_burn = (Process.times.utime + Process.times.stime) - t
            stats_engine.get_stats_no_scope("ControllerCPU/#{path}").record_data_point(cpu_burn)
            agent.transaction_sampler.notice_transaction_cpu_time(cpu_burn)
            
            # do the apdex bucketing
            #
            duration = Time.now.to_f - start
            controller_stat = stats_engine.get_custom_stats("Apdex/#{path}", NewRelic::ApdexStats)
            case
              when failed
              apdex_overall_stat.record_apdex_f    # frustrated
              controller_stat.record_apdex_f
              when duration <= NewRelic::Control.instance['apdex_t']
              apdex_overall_stat.record_apdex_s    # satisfied
              controller_stat.record_apdex_s
              when duration <= 4 * NewRelic::Control.instance['apdex_t']
              apdex_overall_stat.record_apdex_t    # tolerating
              controller_stat.record_apdex_t
            else
              apdex_overall_stat.record_apdex_f    # frustrated
              controller_stat.record_apdex_f
            end
          end
        end
      end
    ensure
      # clear out the name of the traced transaction under all circumstances
      stats_engine.transaction_name = nil
    end
    
    private
    def apdex_overall_stat
      @@newrelic_apdex_overall ||= NewRelic::Agent.instance.stats_engine.get_custom_stats("Apdex", NewRelic::ApdexStats)  
    end
    
  end 
end  
