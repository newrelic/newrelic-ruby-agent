require 'set'

# NewRelic instrumentation for controllers
if defined? ActionController


module ActionController
  class Base
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
        return perform_action_without_newrelic_trace unless Hash === ignore_actions
        only_actions = Array(ignore_actions[:only])
        except_actions = Array(ignore_actions[:except])
        return perform_action_without_newrelic_trace if only_actions.include? action_name.to_sym
        return perform_action_without_newrelic_trace if except_actions.any? && !except_actions.include?(action_name.to_sym)
      end
      
      agent.ensure_started

      # generate metrics for all all controllers (no scope)
      self.class.trace_method_execution "Controller", false, true, true do 
        # generate metrics for this specific action
        path = _determine_metric_path
      
        agent.stats_engine.transaction_name ||= "Controller/#{path}" if agent.stats_engine
      
        self.class.trace_method_execution "Controller/#{path}", true, true, true do 
          # send request and parameter info to the transaction sampler
          
          local_copy = params
          
          if respond_to? :filter_parameters
            local_copy = filter_parameters(params)
          else
            local_copy = params
          end
            
          agent.transaction_sampler.notice_transaction(path, request, local_copy)
        
          t = Process.times.utime + Process.times.stime
          
          begin
            # run the action
            perform_action_without_newrelic_trace
          ensure
            agent.transaction_sampler.notice_transaction_cpu_time((Process.times.utime + Process.times.stime) - t)
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
  
    # ActionWebService is now an optional part of Rails as of 2.0
    if method_defined? :perform_invocation
      add_method_tracer :perform_invocation, 'WebService/#{controller_name}/#{args.first}'
    end
  
    private
      # determine the path that is used in the metric name for
      # the called controller action
      def _determine_metric_path
        if self.class.action_methods.include?(action_name)
          "#{self.class.controller_path}/#{action_name}"
        else
          "#{self.class.controller_path}/(other)"
        end
      end
  end

end

end  


