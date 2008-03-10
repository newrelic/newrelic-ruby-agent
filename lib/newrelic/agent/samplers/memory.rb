module NewRelic::Agent
  class MemorySampler
    def initialize
      # macos of linux
      # TODO support solaris!!
      if RUBY_PLATFORM =~ /(darwin|linux)/
        @ps = "ps -o rsz #{$$}"
      end
      
      if @ps
        agent = NewRelic::Agent.instance
        agent.stats_engine.add_sampled_metric("Memory/Physical") do |stats|
          return if @broken
          memory = `#{@ps}`.split("\n")[1].to_f / 1024
          
          # if for some reason the ps command doesn't work on the resident os,
          # then don't execute it any more.
          if memory > 0
            stats.record_data_point memory
            
          else 
            NewRelic::Agent.instance.log.error "Error attempting to determine resident memory.  Disabling this metric."
            NewRelic::Agent.instance.log.error "Faulty command: `#{@ps}`"
            @broken = true
          end
        end
      end
    end
  end
end

NewRelic::Agent::MemorySampler.new
