class Module
  def trace_method_execution (metric_name)
    stats_engine = Seldon::Agent.agent.stats_engine
    stats = stats_engine.get_stats metric_name
  
    stats_engine.push_scope metric_name 
    t0 = Time.now

    begin
      result = yield
    ensure
      t1 = Time.now
    
      stats_engine.pop_scope
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
  def add_tracer_to_method (method_name, metric_name_code)
    return unless ::SELDON_AGENT_ENABLED
    
    klass = (self === Module) ? "self" : "self.class"
  
    code = <<-CODE
    def #{method_name}_with_trace(*args)
      metric_name = "#{metric_name_code}"
      #{klass}.trace_method_execution("\#{metric_name}") do
        #{method_name}_without_trace *args
      end
    end
    CODE
  
    class_eval code
  
    alias_method "#{method_name}_without_trace", method_name
    alias_method method_name, "#{method_name}_with_trace"
  end

  def remove_tracer_from_method(method_name)
    return unless ::SELDON_AGENT_ENABLED
    
    if method_defined? "#{method_name}_with_trace"
      alias_method method_name, "#{method_name}_without_trace"
      undef_method "#{method_name}_with_trace"
    end
  end
end
