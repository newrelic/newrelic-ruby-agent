module NewRelic::Agent

  # These are stubs for API methods installed when the agent is disabled.

  module MethodTracerShim
    def trace_method_execution(*args); yield; end
    
    def trace_method_execution_no_scope(metric_name); yield; end
    def trace_method_execution_with_scope(*args); yield; end
    def add_method_tracer (*args); end
    def remove_method_tracer(*args); end
  end
  
  # These are the class methods added to support installing custom
  # metric tracers and executing for individual metrics.
  # This module is included in class Module.
  module MethodTracer
    
    # Deprecated: original method preserved for API backward compatibility, use one of the other
    # +trace_method..+ calls.
    def trace_method_execution(metric_name, push_scope, produce_metric, deduct_call_time_from_parent, &block) 
      if push_scope
        trace_method_execution_with_scope(metric_name, produce_metric, deduct_call_time_from_parent, &block)
      else
        trace_method_execution_no_scope(metric_name, &block)
      end
    end
    
    # Trace a given block with stats assigned to the given metric_name.  It does not 
    # provide scoped measurements, meaning whatever is being traced will not 'blame the
    # Controller'--that is to say appear in the breakdown chart. 
    # This is duplicated inline in #add_method_tracer.
    def trace_method_execution_no_scope(metric_name)
      t0 = Time.now.to_f
      stats = NewRelic::Agent.instance.stats_engine.get_stats_no_scope metric_name
      
      begin
        yield
      ensure
        duration = Time.now.to_f - t0              # for some reason this is 3 usec faster than Time - Time
        stats.trace_call(duration, duration)
      end
    end

    # Trace a given block with stats, like #trace_method_execution_no_scope but 
    def trace_method_execution_with_scope(metric_name, produce_metric, deduct_call_time_from_parent, scoped_metric_only=false)
      t0 = Time.now.to_f
      stats = nil
      
      begin
        # Keep a reference to the scope we are pushing so we can do a sanity check making
        # sure when we pop we get the one we 'expected'
        expected_scope = NewRelic::Agent.instance.stats_engine.push_scope(metric_name, t0, deduct_call_time_from_parent)
        
        stats = NewRelic::Agent.instance.stats_engine.get_stats(metric_name, true, scoped_metric_only) if produce_metric
      rescue => e
        NewRelic::Control.instance.log.error("Caught exception in trace_method_execution header. Metric name = #{metric_name}, exception = #{e}")
        NewRelic::Control.instance.log.error(e.backtrace.join("\n"))
      end
      
      begin
        yield
      ensure
        t1 = Time.now.to_f
        duration = t1 - t0
        
        begin
          if expected_scope
            scope = NewRelic::Agent.instance.stats_engine.pop_scope expected_scope, duration, t1
            
            exclusive = duration - scope.children_time
            stats.trace_call(duration, exclusive) if stats
          end
        rescue => e
          NewRelic::Control.instance.log.error("Caught exception in trace_method_execution footer. Metric name = #{metric_name}, exception = #{e}")
          NewRelic::Control.instance.log.error(e.backtrace.join("\n"))
        end
      end
    end
    
    # Add a method tracer to the specified method.  
    # metric_name_code is ruby code that determines the name of the
    # metric to be collected during tracing.  As such, the code
    # should be provided in 'single quote' strings rather than
    # "double quote" strings, so that #{} evaluation happens
    # at traced method execution time.
    # Example: tracing a method :foo, where the metric name is
    # the first argument converted to a string
    #     add_method_tracer :foo, '#{args.first.to_s}'
    # statically defined metric names can be specified as regular strings
    # push_scope specifies whether this method tracer should push
    # the metric name onto the scope stack.
    def add_method_tracer (method_name, metric_name_code, options = {})
      if !options.is_a?(Hash)
        options = {:push_scope => options} 
      end
      # options[:push_scope] true if we are noting the scope of this for
      # stats collection as well as the transaction tracing
      options[:push_scope] = true if options[:push_scope].nil?
      # options[:metric] true if you are tracking stats for a metric, otherwise
      # it's just for transaction tracing.
      options[:metric] = true if options[:metric].nil?
      options[:deduct_call_time_from_parent] = false if options[:deduct_call_time_from_parent].nil? && !options[:metric]
      options[:deduct_call_time_from_parent] = true if options[:deduct_call_time_from_parent].nil?
      options[:code_header] ||= ""
      options[:code_footer] ||= ""
      options[:scoped_metric_only] ||= false
      
      klass = (self === Module) ? "self" : "self.class"
      
      unless method_defined?(method_name) || private_method_defined?(method_name)
        NewRelic::Control.instance.log.warn("Did not trace #{self}##{method_name} because that method does not exist")
        return
      end
      
      traced_method_name = _traced_method_name(method_name, metric_name_code)
      if method_defined? traced_method_name
        NewRelic::Control.instance.log.warn("Attempt to trace a method twice with the same metric: Method = #{method_name}, Metric Name = #{metric_name_code}")
        return
      end
      
      fail "Can't add a tracer where push_scope is false and metric is false" if options[:push_scope] == false && !options[:metric]
      
      if options[:push_scope] == false
        code = <<-CODE
        def #{_traced_method_name(method_name, metric_name_code)}(*args, &block)
          #{options[:code_header]}

          t0 = Time.now.to_f
          stats = NewRelic::Agent.instance.stats_engine.get_stats_no_scope "#{metric_name_code}"

          begin
            #{_untraced_method_name(method_name, metric_name_code)}(*args, &block)
          ensure
            duration = Time.now.to_f - t0
            stats.trace_call(duration, duration)     # for some reason this is 3 usec faster than Time - Time
            #{options[:code_footer]}
          end
        end
      CODE
      else
        code = <<-CODE
      def #{_traced_method_name(method_name, metric_name_code)}(*args, &block)
        #{options[:code_header]}
        result = #{klass}.trace_method_execution_with_scope("#{metric_name_code}", #{options[:metric]}, #{options[:deduct_call_time_from_parent]}, #{options[:scoped_metric_only]}) do
          #{_untraced_method_name(method_name, metric_name_code)}(*args, &block)
        end
        #{options[:code_footer]}
        result
      end
      CODE
      end
      
      class_eval code, __FILE__, __LINE__
      
      alias_method _untraced_method_name(method_name, metric_name_code), method_name
      alias_method method_name, _traced_method_name(method_name, metric_name_code)
      
      NewRelic::Control.instance.log.debug("Traced method: class = #{self}, method = #{method_name}, "+
        "metric = '#{metric_name_code}', options: #{options.inspect}, ")
    end
    
    # Not recommended for production use, because tracers must be removed in reverse-order
    # from when they were added, or else other tracers that were added to the same method
    # may get removed as well.
    def remove_method_tracer(method_name, metric_name_code)
      return unless NewRelic::Control.instance.agent_enabled?
      
      if method_defined? "#{_traced_method_name(method_name, metric_name_code)}"
        alias_method method_name, "#{_untraced_method_name(method_name, metric_name_code)}"
        undef_method "#{_traced_method_name(method_name, metric_name_code)}"
      else
        raise "No tracer for '#{metric_name_code}' on method '#{method_name}'"
      end
    end
    
    private
    
    def _untraced_method_name(method_name, metric_name)
    "#{_sanitize_name(method_name)}_without_trace_#{_sanitize_name(metric_name)}" 
    end
    
    def _traced_method_name(method_name, metric_name)
    "#{_sanitize_name(method_name)}_with_trace_#{_sanitize_name(metric_name)}" 
    end
    
    def _sanitize_name(name)
      name.to_s.tr('^a-z,A-Z,0-9', '_')
    end
  end
end
