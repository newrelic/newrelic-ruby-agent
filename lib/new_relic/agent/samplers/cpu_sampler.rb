module NewRelic::Agent::Samplers
  class CpuSampler < NewRelic::Agent::Sampler
    def initialize
      super :cpu
    end
    def usertime_stats
      @usertime ||= stats_engine.get_stats("CPU/User Time", false)
    end
    def systemtime_stats
      @systemtime ||= stats_engine.get_stats("CPU/System Time", false)
    end
    def poll
      t = Process.times
      @last_utime ||= t.utime
      @last_stime ||= t.stime
      utime = t.utime
      stime = t.stime
      
      systemtime_stats.record_data_point(stime - @last_stime) if (stime - @last_stime) >= 0
      usertime_stats.record_data_point(utime - @last_utime) if (utime - @last_utime) >= 0
      @last_utime = utime
      @last_stime = stime
    end
  end
end

