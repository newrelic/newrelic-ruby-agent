require 'logger'

class Module
  # cattr_accessor is missing from unit test context so we need to hand code
  # the class accessor for the instrumentation log
  def method_tracer_log
    @@method_trace_log ||= Logger.new(STDERR)
  end
  
  def method_tracer_log= (log)
    @@method_trace_log = log
  end
  
  def trace_method_execution (metric_name, push_scope = true, agent = NewRelic::Agent.agent)
    stats_engine = agent.stats_engine
    stats = stats_engine.get_stats metric_name, push_scope
  
    stats_engine.push_scope metric_name if push_scope
    t0 = Time.now

    begin
      result = yield
    ensure
      t1 = Time.now
    
      duration = t1 - t0
      
      if push_scope
        scope = stats_engine.pop_scope 
        exclusive = duration - scope.exclusive_time
      else
        exclusive = duration
      end
      stats.trace_call t1-t0, exclusive
    
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
  #     add_method_tracer :foo, '#{args.first.to_s}'
  # statically defined metric names can be specified as regular strings
  # push_scope specifies whether this method tracer should push
  # the metric name onto the scope stack.
  def add_method_tracer (method_name, metric_name_code, push_scope = true)
    return unless ::SELDON_AGENT_ENABLED
    klass = (self === Module) ? "self" : "self.class"
    
    unless method_defined?(method_name) || private_method_defined?(method_name)
      method_tracer_log.warn("Did not trace #{self}##{method_name} because that method does not exist")
      return
    end
    
    traced_method_name = _traced_method_name(method_name, metric_name_code)
    if method_defined? traced_method_name
      method_tracer_log.warn("Attempt to trace a method twice with the same metric: Method = #{method_name}, Metric Name = #{metric_name_code}")
      return
    end
    
    code = <<-CODE
    def #{_traced_method_name(method_name, metric_name_code)}(*args, &block)
      metric_name = "#{metric_name_code}"
      #{klass}.trace_method_execution("\#{metric_name}", #{push_scope}) do
        #{_untraced_method_name(method_name, metric_name_code)}(*args, &block)
      end
    end
    CODE
  
    class_eval code
  
    alias_method _untraced_method_name(method_name, metric_name_code), method_name
    alias_method method_name, "#{_traced_method_name(method_name, metric_name_code)}"
  end

  # Not recommended for production use, because tracers must be removed in reverse-order
  # from when they were added, or else other tracers that were added to the same method
  # may get removed as well.
  def remove_method_tracer(method_name, metric_name_code)
    return unless ::SELDON_AGENT_ENABLED
    
    if method_defined? "#{_traced_method_name(method_name, metric_name_code)}"
      alias_method method_name, "#{_untraced_method_name(method_name, metric_name_code)}"
      undef_method "#{_traced_method_name(method_name, metric_name_code)}"
    else
      raise Exception.new("No tracer for '#{metric_name_code}' on method '#{method_name}'");
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
