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
      def newrelic_ignore_apdex(*args); end
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
        newrelic_ignore_aspect('do_not_trace', specifiers)
      end
      # Have NewRelic omit apdex measurements on the given actions.  Typically used for 
      # actions that are not user facing or that skew your overall apdex measurement.
      # Accepts :except and :only options, as with #newrelic_ignore.
      def newrelic_ignore_apdex(specifiers={})
        newrelic_ignore_aspect('ignore_apdex', specifiers)
      end
      
      def newrelic_ignore_aspect(property, specifiers={}) # :nodoc:
        if specifiers.empty?
          self.newrelic_write_attr property, true
        elsif ! (Hash === specifiers)
          logger.error "newrelic_#{property} takes an optional hash with :only and :except lists of actions (illegal argument type '#{specifiers.class}')"
        else
          self.newrelic_write_attr property, specifiers
        end
      end
      
      # Should be monkey patched into the controller class implemented with the inheritable attribute mechanism.
      def newrelic_write_attr(attr_name, value) # :nodoc:
        instance_variable_set "@#{attr_name}", value
      end
      def newrelic_read_attr(attr_name) # :nodoc:
        instance_variable_get "@#{attr_name}", value
      end
    end
    
    # Must be implemented in the controller class:
    # Determine the path that is used in the metric name for
    # the called controller action.  Of the form controller_path/action_name
    # 
    def newrelic_metric_path(action_name_override = nil) # :nodoc:
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
      
      # Skip instrumentation based on the value of 'do_not_trace' and if 
      # we aren't calling directly with a block.
      if !block_given? && is_filtered?(self.class.newrelic_read_attr('do_not_trace'))
        # Tell the dispatcher instrumentation that we ignored this action and it shouldn't
        # be counted for the overall HTTP operations measurement.
        Thread.current[:newrelic_ignore_controller] = true
        # Also ignore all instrumentation in the call sequence
        NewRelic::Agent.disable_all_tracing do
          return perform_action_without_newrelic_trace(*args)
        end
      end
      
      # reset this in case we came through a code path where the top level controller is ignored
      Thread.current[:newrelic_ignore_controller] = nil
      
      start = Time.now.to_f
      agent.ensure_worker_thread_started
#      gc_start = GC.respond_to?(:enable_stats) && GC.time      
      # assuming the first argument, if present, is the action name
      path = newrelic_metric_path(args.size > 0 ? args[0] : nil)
      controller_metric = "Controller/#{path}"
      force = block_given? && Hash === args.last && args.last[:force]
      NewRelic::Agent.trace_execution_scoped [controller_metric, "Controller"], :force => force do 
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
          if NewRelic::Agent.is_execution_traced?
            cpu_burn = (Process.times.utime + Process.times.stime) - t
            stats_engine.get_stats_no_scope("ControllerCPU/#{path}").record_data_point(cpu_burn)
            agent.transaction_sampler.notice_transaction_cpu_time(cpu_burn)
#            if gc_start
#              gcstats = stats_engine.get_stats("GC/cumulative")
#              gcstats.record_data_point((GC.time - gc_start)/1000000.0)
#            end
            # do the apdex bucketing
            #
            unless is_filtered?(self.class.newrelic_read_attr('ignore_apdex'))
              duration = Time.now.to_f - start
              controller_stat = stats_engine.get_custom_stats("Apdex/#{path}", NewRelic::ApdexStats)
              case
              when failed
                apdex_overall_stat.record_apdex_f    # frustrated
                controller_stat.record_apdex_f
              when duration <= NewRelic::Control.instance.apdex_t
                apdex_overall_stat.record_apdex_s    # satisfied
                controller_stat.record_apdex_s
              when duration <= 4 * NewRelic::Control.instance.apdex_t
                apdex_overall_stat.record_apdex_t    # tolerating
                controller_stat.record_apdex_t
              else
                apdex_overall_stat.record_apdex_f    # frustrated
                controller_stat.record_apdex_f
              end
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
      NewRelic::Agent.instance.stats_engine.get_custom_stats("Apdex", NewRelic::ApdexStats)  
    end
    
    def is_filtered?(ignore_actions)
      case ignore_actions
        when nil; false
        when Hash
        only_actions = Array(ignore_actions[:only])
        except_actions = Array(ignore_actions[:except])
        only_actions.include?(action_name.to_sym) || (except_actions.any? && !except_actions.include?(action_name.to_sym))
      else
        true
      end
    end
  end 
end  
