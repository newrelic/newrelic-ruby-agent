
module NewRelic::Agent::Instrumentation
  # == NewRelic instrumentation for controllers
  #
  # This instrumentation is applied to the action controller by default if the agent
  # is actively collecting statistics.  It will collect statistics for the 
  # given action.
  #
  # In cases where you don't want to instrument the top level action, but instead
  # have other methods which are dispatched to by your action, and you want to treat
  # these as distinct actions, then what you need to do is use
  # #perform_action_with_newrelic_trace
  #
  module ControllerInstrumentation
    
    if defined? JRuby
      @@newrelic_java_classes_missing = false
      begin
        require 'java'
        include_class 'java.lang.management.ManagementFactory'
        include_class 'com.sun.management.OperatingSystemMXBean'
      rescue
        @@newrelic_java_classes_missing = true
      end
    end
    
    def self.included(clazz) # :nodoc:
      clazz.extend(ClassMethods)
    end
    
    # This module is for importing stubs when the agent is disabled
    module ClassMethodsShim # :nodoc:
      def newrelic_ignore(*args); end
      def newrelic_ignore_apdex(*args); end
    end
    
    module Shim # :nodoc:
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
      
      # Should be monkey patched into the controller class implemented
      # with the inheritable attribute mechanism.
      def newrelic_write_attr(attr_name, value) # :nodoc:
        instance_variable_set "@#{attr_name}", value
      end
      def newrelic_read_attr(attr_name) # :nodoc:
        instance_variable_get "@#{attr_name}"
      end
      
      # Add transaction tracing to the given method.  This will treat
      # the given method as a main entrypoint for instrumentation, just
      # like controller actions are treated by default.  Useful especially
      # for background tasks. 
      #
      # Example for background job:
      #   class Job
      #     include NewRelic::Agent::Instrumentation::ControllerInstrumentation
      #     def run(task)
      #        ...
      #     end
      #     # Instrument run so tasks show up under task.name.  Note single
      #     # quoting to defer eval to runtime.
      #     add_transaction_tracer :run, :name => '#{args[0].name}'
      #   end
      #
      # Here's an example of a controller that uses a dispatcher
      # action to invoke operations which you want treated as top
      # level actions, so they aren't all lumped into the invoker
      # action.
      #      
      #   MyController < ActionController::Base
      #     include NewRelic::Agent::Instrumentation::ControllerInstrumentation
      #     # dispatch the given op to the method given by the service parameter.
      #     def invoke_operation
      #       op = params['operation']
      #       send op
      #     end
      #     # Ignore the invoker to avoid double counting
      #     newrelic_ignore :only => 'invoke_operation'
      #     # Instrument the operations:
      #     add_transaction_tracer :print
      #     add_transaction_tracer :show
      #     add_transaction_tracer :forward
      #   end
      #
      # See NewRelic::Agent::Instrumentation::ControllerInstrumentation#perform_action_with_newrelic_trace
      # for the full list of available options.
      #
      def add_transaction_tracer(method, options={})
        # The metric path:
        options[:name] ||= method.to_s
        options_arg = []
        options.each do |key, value|
          options_arg << %Q[:#{key} => #{value.is_a?(Symbol) ? value.inspect : %Q["#{value.to_s}"]}]
        end
        class_eval <<-EOC
        def #{method.to_s}_with_newrelic_transaction_trace(*args, &block)
          NewRelic::Agent::Instrumentation::DispatcherInstrumentation.newrelic_dispatcher_start
          perform_action_with_newrelic_trace(#{options_arg.join(',')}) do
            #{method.to_s}_without_newrelic_transaction_trace(*args, &block)
          end
        ensure
          NewRelic::Agent::Instrumentation::DispatcherInstrumentation.newrelic_dispatcher_finish
        end
        EOC
        alias_method "#{method.to_s}_without_newrelic_transaction_trace", method.to_s
        alias_method method.to_s, "#{method.to_s}_with_newrelic_transaction_trace"
      end
    end
    
    # Must be implemented in the controller class:
    # Determine the path that is used in the metric name for
    # the called controller action.  Of the form controller_path/action_name
    # 
    def newrelic_metric_path(action_name_override = nil) # :nodoc:
      raise "Not implemented!"
    end
    
    # Yield to the given block with NewRelic tracing.  Used by 
    # default instrumentation on controller actions in Rails and Merb.
    # But it can also be used in custom instrumentation of controller
    # methods and background tasks.
    #
    # Here's a more verbose version of the example shown in
    # <tt>ClassMethods#add_transaction_tracer</tt> using this method instead of
    # #add_transaction_tracer.
    #
    # Below is a controller with an +invoke_operation+ action which
    # dispatches to more specific operation methods based on a
    # parameter (very dangerous, btw!).  With this instrumentation,
    # the +invoke_operation+ action is ignored but the operation
    # methods show up in RPM as if they were first class controller
    # actions
    #    
    #   MyController < ActionController::Base
    #     include NewRelic::Agent::Instrumentation::ControllerInstrumentation
    #     # dispatch the given op to the method given by the service parameter.
    #     def invoke_operation
    #       op = params['operation']
    #       perform_action_with_newrelic_trace(:name => op) do
    #         send op, params['message']
    #       end
    #     end
    #     # Ignore the invoker to avoid double counting
    #     newrelic_ignore :only => 'invoke_operation'
    #   end
    #
    # By passing a block in combination with specific arguments, you can 
    # invoke this directly to capture high level information in
    # several contexts:
    #
    # * Pass <tt>:category => :controller</tt> and <tt>:name => actionname</tt>
    #   to treat the block as if it were a controller action, invoked
    #   inside a real action.  <tt>:name</tt> is the name of the method, and is
    #   used in the metric name.
    #
    # When invoked directly, pass in a block to measure with some
    # combination of options:
    #
    # * <tt>:category => :controller</tt> indicates that this is a
    #   controller action and will appear with all the other actions.  This
    #   is the default.
    # * <tt>:category => :task</tt> indicates that this is a
    #   background task and will show up in RPM with other background
    #   tasks instead of in the controllers list
    # * <tt>:category => :rack</tt> if you are instrumenting a rack
    #   middleware call.  The <tt>:name</tt> is optional, useful if you 
    #   have more than one potential transaction in the #call.
    # * <tt>:category => :uri</tt> indicates that this is a
    #   web transaction whose name is a normalized URI, where  'normalized'
    #   means the URI does not have any elements with data in them such
    #   as in many REST URIs.
    # * <tt>:name => action_name</tt> is used to specify the action
    #   name used as part of the metric name
    # * <tt>:force => true</tt> indicates you should capture all
    #   metrics even if the #newrelic_ignore directive was specified
    # * <tt>:class_name => aClass.name</tt> is used to override the name
    #   of the class when used inside the metric name.  Default is the
    #   current class.
    # * <tt>:path => metric_path</tt> is *deprecated* in the public API.  It
    #   allows you to set the entire metric after the category part.  Overrides
    #   all the other options.
    #
    # If a single argument is passed in, it is treated as a metric
    # path.  This form is deprecated.
    def perform_action_with_newrelic_trace(*args, &block)

      # Skip instrumentation based on the value of 'do_not_trace' and if 
      # we aren't calling directly with a block.
      if !block_given? && _is_filtered?('do_not_trace')
        # Tell the dispatcher instrumentation that we ignored this action and it shouldn't
        # be counted for the overall HTTP operations measurement.
        Thread.current[:newrelic_ignore_controller] = true
        # Also ignore all instrumentation in the call sequence
        NewRelic::Agent.disable_all_tracing do
          return perform_action_without_newrelic_trace(*args)
        end
      end
      agent = NewRelic::Agent.instance
      stats_engine = agent.stats_engine
      
      # reset this in case we came through a code path where the top level controller is ignored
      Thread.current[:newrelic_ignore_controller] = nil
      apdex_start = (Thread.current[:started_on] || Thread.current[:newrelic_dispatcher_start] || Time.now).to_f
      force = false
      # If a block was passed in, then the arguments represent options for the instrumentation,
      # not app method arguments.
      if block_given? && args.any?
        force = args.last.is_a?(Hash) && args.last[:force]
        category, path = _convert_args_to_path(args)
      else
        category = 'Controller'
        path = newrelic_metric_path
      end
      metric_name = category + '/' + path 

      return perform_action_with_newrelic_profile(metric_name, path, args, &block) if NewRelic::Control.instance.profiling?

      agent.ensure_worker_thread_started
      
      NewRelic::Agent.trace_execution_scoped [metric_name, "Controller"], :force => force do
        # Last one (innermost) to set the transaction name on the call stack wins.
        stats_engine.transaction_name = metric_name
        available_params = self.respond_to?(:params) ? params : {} 
        local_params = (respond_to? :filter_parameters) ? filter_parameters(available_params) : available_params
        available_request = (respond_to? :request) ? request : nil
        agent.transaction_sampler.notice_transaction(path, available_request, local_params)
        
        jruby_cpu_start = _jruby_cpu_time
        process_cpu_start = _process_cpu
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
            cpu_burn = nil
            if process_cpu_start
              cpu_burn = _process_cpu - process_cpu_start
            elsif jruby_cpu_start
              cpu_burn = _jruby_cpu_time - jruby_cpu_start
              stats_engine.get_stats_no_scope(NewRelic::Metrics::USER_TIME).record_data_point(cpu_burn)
            end
            agent.transaction_sampler.notice_transaction_cpu_time(cpu_burn) if cpu_burn
            
            # do the apdex bucketing
            #
            unless _is_filtered?('ignore_apdex')
              ending = Time.now.to_f
              # this uses the start of the dispatcher or the mongrel
              # thread: causes apdex to show too little capacity
              apdex_overall(apdex_start, ending, failed)
              # this uses the start time of the controller action:
              # does not include capacity problems since those aren't
              # per controller
              apdex_controller(apdex_start, ending, failed, path)
            end
          end
        end
      end
    end
    
    # Experimental
    def perform_action_with_newrelic_profile(metric_name, path, args)
      agent = NewRelic::Agent.instance
      stats_engine = agent.stats_engine
      NewRelic::Agent.trace_execution_scoped [metric_name, "Controller"] do
        stats_engine.transaction_name = metric_name
        NewRelic::Agent.disable_all_tracing do
          available_params = self.respond_to?(:params) ? params : {} 
          # Not sure if we need to get the params and request...
          local_params = (respond_to? :filter_parameters) ? filter_parameters(available_params) : available_params
          available_request = (respond_to? :request) ? request : nil
          agent.transaction_sampler.notice_transaction(path, available_request, local_params)

          # turn on profiling
          profile = RubyProf.profile do
            if block_given?
              yield
            else
              perform_action_without_newrelic_trace(*args)
            end
          end
          agent.transaction_sampler.notice_profile profile
        end
      end
    end
    
  private
  
    def apdex_overall_stat
      NewRelic::Agent.instance.stats_engine.get_custom_stats("Apdex", NewRelic::ApdexStats)  
    end
    
    def apdex_overall(start, ending, failed)
      record_apdex(apdex_overall_stat, (ending - start), failed)
    end
    
    def apdex_controller(start, ending, failed, path)
      controller_stat = NewRelic::Agent.instance.stats_engine.get_custom_stats("Apdex/#{path}", NewRelic::ApdexStats)
      record_apdex(controller_stat, (ending - start), failed)
    end
    
    def record_apdex(stat, duration, failed)
      apdex_t = NewRelic::Control.instance.apdex_t
      case
        when failed
        stat.record_apdex_f
        when duration <= apdex_t
        stat.record_apdex_s
        when duration <= 4 * apdex_t
        stat.record_apdex_t
      else
        stat.record_apdex_f
      end
    end
    
    protected
    
    def _convert_args_to_path(args)
      options =  args.last.is_a?(Hash) ? args.pop : {}
      category = 'Controller'
      unless path = options[:path]
        category = case options[:category]
          when :controller, nil then 'Controller'
          when :task then 'OtherTransaction/Background' # 'Task'
          when :rack then 'Controller/Rack' #'WebTransaction/Rack'
          when :uri then 'Controller' #'WebTransaction/Uri'
          # for internal use only
          when :sinatra then 'Controller/Sinatra' #'WebTransaction/Uri'
        else options[:category].to_s.capitalize
        end
        # To be consistent with the ActionController::Base#controller_path used in rails to determine the
        # metric path, we drop the controller off the end of the path if there is one.
        action = options[:name] || args.first 
        force = options[:force]
        metric_class = options[:class_name] || (self.is_a?(Class) ? self.name : self.class.name)
        
        path = metric_class
        path += ('/' + action) if action
      end
      [category, path]
    end
    # Filter out 
    def _is_filtered?(key)
      ignore_actions = self.class.newrelic_read_attr(key) if self.class.respond_to? :newrelic_read_attr
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
    
    def _process_cpu
      return nil if defined? JRuby
      p = Process.times
      p.stime + p.utime
    end
    
    def _jruby_cpu_time # :nodoc:
      return nil unless defined? JRuby and not @@newrelic_java_classes_missing 
      threadMBean = ManagementFactory.getThreadMXBean()
      java_utime = threadMBean.getCurrentThreadUserTime()  # ns
      -1 == java_utime ? 0.0 : java_utime/1e9
    end
        
  end 
end  
