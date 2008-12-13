# NewRelic instrumentation for controllers


# This method is used to directly trace controller actions
#
# INTERNAL ONLY...DO NOT CALL DIRECTLY
#
def new_relic_trace_controller_action(action_name)
  agent = NewRelic::Agent.instance
  
  start = Time.now.to_f
  agent.ensure_worker_thread_started
  
  Thread.current[:controller_ignored] = false     # if we don't do this the dispatcher ignores this call
  
  # generate metrics for all all controllers (no scope)
  self.class.trace_method_execution_no_scope "Controller" do 
    # generate metrics for this specific action
    path = _determine_metric_path(action_name)
    
    agent.stats_engine.transaction_name ||= "Controller/#{path}" if agent.stats_engine
    
    self.class.trace_method_execution_with_scope "Controller/#{path}", true, true do 
      # send request and parameter info to the transaction sampler
      
      local_params = (respond_to? :filter_parameters) ? filter_parameters(params) : params
      
      agent.transaction_sampler.notice_transaction(path, request, local_params)
      
      t = Process.times.utime + Process.times.stime
      
      begin
        # run the action
        yield
      ensure
        cpu_burn = (Process.times.utime + Process.times.stime) - t
        agent.transaction_sampler.notice_transaction_cpu_time(cpu_burn)

        duration = Time.now.to_f - start
        
        # do the apdex bucketing
        if duration <= @@newrelic_apdex_t
          @@newrelic_apdex_overall.record_apdex_s cpu_burn    # satisfied
          agent.stats_engine.get_stats_no_scope("Apdex/#{path}").record_apdex_s cpu_burn
        elsif duration <= (4 * @@newrelic_apdex_t)
          @@newrelic_apdex_overall.record_apdex_t cpu_burn    # tolerating
          agent.stats_engine.get_stats_no_scope("Apdex/#{path}").record_apdex_t cpu_burn
        else
          @@newrelic_apdex_overall.record_apdex_f cpu_burn    # frustrated
          agent.stats_engine.get_stats_no_scope("Apdex/#{path}").record_apdex_f cpu_burn
        end
        
      end
    end
  end
  
ensure
  # clear out the name of the traced transaction under all circumstances
  agent.stats_engine.transaction_name = nil
end



if defined? ActionController 

  ActionController::Base.class_eval do
    
    class << self
      @@newrelic_apdex_t = NewRelic::Agent.instance.apdex_t
      @@newrelic_apdex_overall = NewRelic::Agent.instance.stats_engine.get_stats_no_scope("Apdex")
    end
    
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
    
    def perform_action_with_newrelic_trace
      agent = NewRelic::Agent.instance
      ignore_actions = self.class.read_inheritable_attribute('do_not_trace')
      # Skip instrumentation based on the value of 'do_not_trace'
      if ignore_actions
        should_skip = false
        
        if Hash === ignore_actions
          only_actions = Array(ignore_actions[:only])
          except_actions = Array(ignore_actions[:except])
          should_skip = true if only_actions.include? action_name.to_sym
          should_skip = true if except_actions.any? && !except_actions.include?(action_name.to_sym)
        else
          should_skip = true
        end
        
        if should_skip
          Thread.current[:controller_ignored] = true
          return perform_action_without_newrelic_trace
        end
      end
      
      start = Time.now.to_f
      agent.ensure_worker_thread_started
      
      # generate metrics for all all controllers (no scope)
      self.class.trace_method_execution_no_scope "Controller" do 
        # generate metrics for this specific action
        path = _determine_metric_path
        
        agent.stats_engine.transaction_name ||= "Controller/#{path}" if agent.stats_engine
        
        self.class.trace_method_execution_with_scope "Controller/#{path}", true, true do 
          # send request and parameter info to the transaction sampler
          
          local_params = (respond_to? :filter_parameters) ? filter_parameters(params) : params
          
          agent.transaction_sampler.notice_transaction(path, request, local_params)
          
          t = Process.times.utime + Process.times.stime
          
          begin
            # run the action
            perform_action_without_newrelic_trace
          ensure
            cpu_burn = (Process.times.utime + Process.times.stime) - t
            agent.transaction_sampler.notice_transaction_cpu_time(cpu_burn)

            duration = Time.now.to_f - start
            
            # do the apdex bucketing
            if duration <= @@newrelic_apdex_t
              @@newrelic_apdex_overall.record_apdex_s cpu_burn    # satisfied
              agent.stats_engine.get_stats_no_scope("Apdex/#{path}").record_apdex_s cpu_burn
            elsif duration <= (4 * @@newrelic_apdex_t)
              @@newrelic_apdex_overall.record_apdex_t cpu_burn    # tolerating
              agent.stats_engine.get_stats_no_scope("Apdex/#{path}").record_apdex_t cpu_burn
            else
              @@newrelic_apdex_overall.record_apdex_f cpu_burn    # frustrated
              agent.stats_engine.get_stats_no_scope("Apdex/#{path}").record_apdex_f cpu_burn
            end
            
          end
        end
      end
      
    ensure
      # clear out the name of the traced transaction under all circumstances
      agent.stats_engine.transaction_name = nil
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
    def _determine_metric_path(action = action_name)
      if self.class.action_methods.include?(action)
        "#{self.class.controller_path}/#{action}"
      else
        "#{self.class.controller_path}/(other)"
      end
    end
  end  
else
  NewRelic::Agent.instance.log.debug "WARNING: ActionController instrumentation not added"
end  
