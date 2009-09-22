module NewRelic::Agent::Samplers
  class CpuSampler < NewRelic::Agent::Sampler
    if defined? JRuby
      begin
        require 'java'
        include_class 'java.lang.management.ManagementFactory'
        include_class 'com.sun.management.OperatingSystemMXBean'
      rescue
        @@java_classes_missing = true
      end
    end
    attr_reader :last_time
    def initialize
      super :cpu
      poll
    end
    def user_util_stats
      stats_engine.get_stats_no_scope("CPU/User/Utilization")
    end
    def system_util_stats
      stats_engine.get_stats_no_scope("CPU/System/Utilization")
    end
    def usertime_stats
      stats_engine.get_stats_no_scope("CPU/User Time")
    end
    def systemtime_stats
      stats_engine.get_stats_no_scope("CPU/System Time")
    end
    
    def self.supported_on_this_platform?
      (not defined?(Java)) or (defined?(JRuby))
    end
    
    def poll
      now = Time.now
      if defined?(JRuby) and not @@java_classes_missing
        osMBean = ManagementFactory.getOperatingSystemMXBean()
        java_utime = osMBean.getProcessCpuTime()  # ns
        t = Struct::Tms.new
        t.utime = t.stime = (-1 == java_utime ? 0.0 : java_utime/1e9)
      else
        t = Process.times
      end
      if @last_time
        elapsed = now - @last_time
        return if elapsed < 1 # Causing some kind of math underflow
        num_processors = NewRelic::Control.instance.local_env.processors || 1
        usertime = t.utime - @last_utime
        systemtime = t.stime - @last_stime

        systemtime_stats.record_data_point(systemtime) if systemtime >= 0
        usertime_stats.record_data_point(usertime) if usertime >= 0
        
        # Calculate the true utilization by taking cpu times and dividing by
        # elapsed time X num_processors.
        user_util_stats.record_data_point usertime / (elapsed * num_processors)
        system_util_stats.record_data_point systemtime / (elapsed * num_processors)
      end
      @last_utime = t.utime
      @last_stime = t.stime
      @last_time = now
    end
  end
end

