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

if defined? ActionController 

  ActionController::Base.class_eval do
    
    @@newrelic_apdex_t = NewRelic::Agent.instance.apdex_t
    @@newrelic_apdex_overall = NewRelic::Agent.instance.stats_engine.get_stats_no_scope("Apdex")
    
    # Have NewRelic ignore actions in this controller.  Specify the actions as hash options
    # using :except and :only.  If no actions are specified, all actions are ignored.
    def self.newrelic_ignore(specifiers={})
      if specifiers.empty?
        write_inheritable_attribute('do_not_trace', true)
      elsif ! (Hash === specifiers)
        logger.error "newrelic_ignore takes an optional hash with :only and :except lists of actions (illegal argument type '#{specifiers.class}')"
      else
        write_inheritable_attribute('do_not_trace', specifiers)
      end
    end
    
    # Perform the current action with NewRelic tracing.  Used in a method
    # chain via aliasing.  Call directly if you want to instrument a specifc
    # block as if it were an action.  Pass the block along with the path.
    # The metric is named according to the action name, or the given path if called
    # directly.  
    def perform_action_with_newrelic_trace(action_name_override=nil)
      agent = NewRelic::Agent.instance
      stats_engine = agent.stats_engine

      ignore_actions = self.class.read_inheritable_attribute('do_not_trace')
      # Skip instrumentation based on the value of 'do_not_trace' and if 
      # we aren't calling directly with a block.
      should_skip = !block_given? && case ignore_actions
          when nil
            false
          when Hash
            only_actions = Array(ignore_actions[:only])
            except_actions = Array(ignore_actions[:except])
            only_actions.include?(action_name.to_sym) || (except_actions.any? && !except_actions.include?(action_name.to_sym))
          else
            true
          end
      if should_skip
        begin
          return perform_action_without_newrelic_trace
        ensure
          # Tell the dispatcher instrumentation that we ignored this action and it shouldn't
          # be counted for the overall HTTP operations measurement.  The if.. appears here
          # because we might be ignoring the top level action instrumenting but instrumenting
          # a direct invocation that already happened, so we need to make sure if this var
          # has already been set to false we don't reset it.
          Thread.current[:controller_ignored] = true if Thread.current[:controller_ignored].nil?
        end
      end

      Thread.current[:controller_ignored] = false
      
      start = Time.now.to_f
      agent.ensure_worker_thread_started
      
      # generate metrics for all all controllers (no scope)
      self.class.trace_method_execution_no_scope "Controller" do 
        # generate metrics for this specific action
        path = _determine_metric_path(action_name_override)
        stats_engine.transaction_name ||= "Controller/#{path}" if stats_engine
        
        self.class.trace_method_execution_with_scope "Controller/#{path}", true, true do 
          # send request and parameter info to the transaction sampler
          
          local_params = (respond_to? :filter_parameters) ? filter_parameters(params) : params
          
          agent.transaction_sampler.notice_transaction(path, request, local_params)
          
          t = Process.times.utime + Process.times.stime
          
          begin
            # run the action
            if block_given?
              yield
            else
              perform_action_without_newrelic_trace
            end
          ensure
            cpu_burn = (Process.times.utime + Process.times.stime) - t
            agent.transaction_sampler.notice_transaction_cpu_time(cpu_burn)

            duration = Time.now.to_f - start
            # do the apdex bucketing
            if duration <= @@newrelic_apdex_t
              @@newrelic_apdex_overall.record_apdex_s cpu_burn    # satisfied
              stats_engine.get_stats_no_scope("Apdex/#{path}").record_apdex_s cpu_burn
            elsif duration <= (4 * @@newrelic_apdex_t)
              @@newrelic_apdex_overall.record_apdex_t cpu_burn    # tolerating
              stats_engine.get_stats_no_scope("Apdex/#{path}").record_apdex_t cpu_burn
            else
              @@newrelic_apdex_overall.record_apdex_f cpu_burn    # frustrated
              stats_engine.get_stats_no_scope("Apdex/#{path}").record_apdex_f cpu_burn
            end
            
          end
        end
      end
      
    ensure
      # clear out the name of the traced transaction under all circumstances
      stats_engine.transaction_name = nil
    end
    
    # Compare with #alias_method_chain, which is not available in 
    # Rails 1.1:
    alias_method :perform_action_without_newrelic_trace, :perform_action
    alias_method :perform_action, :perform_action_with_newrelic_trace
    private :perform_action
    
    add_method_tracer :render, 'View/#{_determine_metric_path}/Rendering'
    
    private
    # determine the path that is used in the metric name for
    # the called controller action
    def _determine_metric_path(action_name_override = nil)
      action_part = action_name_override || action_name
      if action_name_override || self.class.action_methods.include?(action_part)
        "#{self.class.controller_path}/#{action_part}"
      else
        "#{self.class.controller_path}/(other)"
      end
    end
  end  
else
  NewRelic::Agent.instance.log.debug "WARNING: ActionController instrumentation not added"
end  
