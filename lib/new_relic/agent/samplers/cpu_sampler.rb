module NewRelic::Agent::Samplers
  class CpuSampler < NewRelic::Agent::Sampler
    def initialize
      super :cpu
      poll
    end
    def user_util_stats
      @userutil ||= stats_engine.get_stats("CPU/User/Utilization", false)
    end
    def system_util_stats
      @systemutil ||= stats_engine.get_stats("CPU/System/Utilization", false)
    end
    def usertime_stats
      @usertime ||= stats_engine.get_stats("CPU/User Time", false)
    end
    def systemtime_stats
      @systemtime ||= stats_engine.get_stats("CPU/System Time", false)
    end
    def poll
      now = Time.now
      t = Process.times
      if @last_time
        num_processors = NewRelic::Control.instance.local_env.processors || 1
        usertime = t.utime - @last_utime
        systemtime = t.stime - @last_stime

        systemtime_stats.record_data_point(systemtime) if systemtime >= 0
        usertime_stats.record_data_point(usertime) if usertime >= 0
        
        # Calculate the true utilization by taking cpu times and dividing by
        # elapsed time X num_processors.
        elapsed = now - @last_time
        user_util_stats.record_data_point usertime / (elapsed * num_processors)
        system_util_stats.record_data_point systemtime / (elapsed * num_processors)
      end
      @last_utime = t.utime
      @last_stime = t.stime
      @last_time = now
    end
  end
end

