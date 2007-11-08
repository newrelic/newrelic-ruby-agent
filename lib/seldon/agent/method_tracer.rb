class Module
  def trace_method_execution (metric_name, push_scope = true)
    stats_engine = Seldon::Agent.agent.stats_engine
    stats = stats_engine.get_stats metric_name, push_scope
  
    stats_engine.push_scope metric_name if push_scope
    t0 = Time.now

    begin
      result = yield
    ensure
      t1 = Time.now
    
      stats_engine.pop_scope if push_scope
      stats.trace_call t1-t0
    
      result 
    end
  end

  # Add a method tracer to the specified method.  
  # metric_name_code is ruby code that determines the name of the
  # metric to be collected during tracing.  As such, the code
  # should be provided in 'single quoute' strings rather than
  # "double quote" strings, so that #{} evaluation happens
  # at traced method execution time.
  # Example: tracing a method :foo, where the metric name is
  # the first argument converted to a string
  #     add_tracer_to_method :foo, '#{args.first.to_s}
  # statically defined metric names can be specified as regular strings
  def add_tracer_to_method (method_name, metric_name_code, push_scope = true)
    return unless ::SELDON_AGENT_ENABLED
  
    klass = (self === Module) ? "self" : "self.class"
  
    code = <<-CODE
    def #{traced_method_name(method_name, metric_name_code)}(*args)
      metric_name = "#{metric_name_code}"
      #{klass}.trace_method_execution("\#{metric_name}", #{push_scope}) do
        #{untraced_method_name(method_name, metric_name_code)} *args
      end
    end
    CODE
  
    class_eval code
  
    alias_method untraced_method_name(method_name, metric_name_code), method_name
    alias_method method_name, "#{traced_method_name(method_name, metric_name_code)}"
  end

  # Not recommended for production use, because tracers must be removed in reverse-order
  # from when they were added, or else other tracers that were added to the same method
  # may get removed as well.
  def remove_tracer_from_method(method_name, metric_name_code)
    return unless ::SELDON_AGENT_ENABLED
    
    if method_defined? "#{traced_method_name(method_name, metric_name_code)}"
      alias_method method_name, "#{untraced_method_name(method_name, metric_name_code)}"
      undef_method "#{traced_method_name(method_name, metric_name_code)}"
    else
      raise Exception.new("No tracer for '#{metric_name_code}' on method '#{method_name}'");
    end
  end

  def untraced_method_name(method_name, metric_name)
    "#{method_name}_without_trace_#{method_name_modifier(metric_name)}" 
  end
  
  def traced_method_name(method_name, metric_name)
    "#{method_name}_with_trace_#{method_name_modifier(metric_name)}" 
  end
  
  def method_name_modifier(metric_name)
    metric_name.tr('^a-z,A-Z,0-9', '_')
  end
end
