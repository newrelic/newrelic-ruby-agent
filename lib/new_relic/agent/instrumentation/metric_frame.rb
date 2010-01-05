# A struct holding the information required to measure a controller
# action.  This is put on the thread local.  Handles the issue of
# re-entrancy, or nested action calls.
class NewRelic::Agent::Instrumentation::MetricFrame # :nodoc:
  attr_accessor :start, :apdex_start, :exception, 
                :filtered_params, :available_request, :force_flag, 
                :jruby_cpu_start, :process_cpu_start
  
  def self.current
    Thread.current[:newrelic_metric_frame] ||= new
  end
  
  @@java_classes_loaded = false
  if defined? JRuby
    begin
      require 'java'
      include_class 'java.lang.management.ManagementFactory'
      include_class 'com.sun.management.OperatingSystemMXBean'
      @@java_classes_loaded = true
    rescue Exception => e
    end
  end
  
  attr_reader :depth
  
  def initialize
    @start = Time.now.to_f
    @path_stack = [] # stack of [controller, path] elements
    @jruby_cpu_start = jruby_cpu_time
    @process_cpu_start = process_cpu
  end
  
  def push(category, path)
    @path_stack.push [category, path]
  end
  
  # This needs to be called after entering the call to trace the controller action, otherwise
  # the controller action blames itself.  It gets reset in the normal #pop call.
  def start_transaction
    NewRelic::Agent.instance.stats_engine.start_transaction metric_name
    # Only push the transaction context info once, on entry:
    if @path_stack.size == 1
      NewRelic::Agent.instance.transaction_sampler.notice_transaction(metric_name, available_request, filtered_params)
    end
  end
  
  def category
    @path_stack.last.first  
  end
  def path
    @path_stack.last.last
  end
  
  def pop
    category, path = @path_stack.pop
    if category.nil?
      NewRelic::Control.instance.log.error "Underflow in metric frames: #{caller.join("\n   ")}"
    end
    # change the transaction name back to whatever was on the stack.  
    if @path_stack.empty?
      Thread.current[:newrelic_metric_frame] = nil
      if NewRelic::Agent.is_execution_traced?
        cpu_burn = nil
        if @process_cpu_start
          cpu_burn = process_cpu - @process_cpu_start
        elsif @jruby_cpu_start
          cpu_burn = jruby_cpu_time - @jruby_cpu_start
          NewRelic::Agent.get_stats_no_scope(NewRelic::Metrics::USER_TIME).record_data_point(cpu_burn)
        end
        NewRelic::Agent.instance.transaction_sampler.notice_transaction_cpu_time(cpu_burn) if cpu_burn
        NewRelic::Agent.instance.histogram.process(Time.now.to_f - start)
      end      
    end
    NewRelic::Agent.instance.stats_engine.transaction_name = metric_name
  end
  
  def record_apdex
    ending = Time.now.to_f
    summary_stat = NewRelic::Agent.instance.stats_engine.get_custom_stats("Apdex", NewRelic::ApdexStats)
    controller_stat = NewRelic::Agent.instance.stats_engine.get_custom_stats("Apdex/#{path}", NewRelic::ApdexStats)
    update_apdex(summary_stat, ending - apdex_start, exception)
    update_apdex(controller_stat, ending - start, exception)
  end
  
  def metric_name
    return nil if @path_stack.empty?
    category + '/' + path 
  end
  
  # Return the array of metrics to record for the current metric frame.
  def recorded_metrics
    metrics = [ metric_name ]
    if @path_stack.size == 1
      if category.starts_with? "Controller" 
        metrics += ["Controller", "HttpDispatcher"]
      else
        metrics += ["#{category}/all", "OtherTransaction/all"]
      end
    end
    metrics
  end
  
  private
  
  def update_apdex(stat, duration, failed)
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
  
  def process_cpu
    return nil if defined? JRuby
    p = Process.times
    p.stime + p.utime
  end
  
  def jruby_cpu_time # :nodoc:
    return nil unless @@java_classes_loaded
    threadMBean = ManagementFactory.getThreadMXBean()
    java_utime = threadMBean.getCurrentThreadUserTime()  # ns
    -1 == java_utime ? 0.0 : java_utime/1e9
  end
  
end