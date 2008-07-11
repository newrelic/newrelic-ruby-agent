module NewRelic::Agent
  class CPUSampler
    def initialize
      t = Process.times
      @last_utime = t.utime
      @last_stime = t.stime
  
      agent = NewRelic::Agent.instance
  
      agent.stats_engine.add_sampled_metric("CPU/User Time") do | stats |
        utime = Process.times.utime
        stats.record_data_point utime - @last_utime
        @last_utime = utime
      end
  
      agent.stats_engine.add_sampled_metric("CPU/System Time") do | stats |
        stime = Process.times.stime
        stats.record_data_point stime - @last_stime
        @last_stime = stime
      end
    end
  end
end

NewRelic::Agent::CPUSampler.new
