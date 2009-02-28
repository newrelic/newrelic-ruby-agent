module NewRelic::Agent::Samplers
  class CpuSampler < NewRelic::Agent::Sampler
    def initialize
      super :cpu
    end

    def poll
      @usertime ||= stats_engine.get_stats("CPU/User Time", false)
      @systemtime ||= stats_engine.get_stats("CPU/System Time", false)
      t = Process.times
      @last_utime ||= t.utime
      @last_stime ||= t.stime
      utime = t.utime
      stime = t.stime
      
      @systemtime.record_data_point(stime - @last_stime) if (stime - @last_stime) >= 0
      @usertime.record_data_point(utime - @last_utime) if (utime - @last_utime) >= 0
      @last_utime = utime
      @last_stime = stime
    end
  end
end
# CPU sampling like this doesn't work for jruby
# NewRelic::Agent::CPUSampler.new unless defined? Java
