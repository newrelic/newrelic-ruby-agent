module NewRelic::Agent
  class MemorySampler
    def initialize
      if RUBY_PLATFORM =~ /java/
        platform = %x[uname -s].downcase
      else
        platform = RUBY_PLATFORM.downcase
      end
      
      # macos, linux, solaris
      if platform =~ /darwin|linux/
        @ps = "ps -o rsz"
      elsif platform =~ /freebsd/
        @ps = "ps -o rss"
      elsif platform =~ /solaris/
        @ps = "/usr/bin/ps -o rss -p"
      end
      if !@ps
        NewRelic::Config.instance.log.warn "Unsupported platform for getting memory: #{platform}"
      else
        @broken = false
        
        agent = NewRelic::Agent.instance        
        agent.stats_engine.add_sampled_metric("Memory/Physical") do |stats|
          if !@broken
            begin
              process = $$
              memory = `#{@ps} #{process}`.split("\n")[1].to_f / 1024

              # if for some reason the ps command doesn't work on the resident os,
              # then don't execute it any more.
              if memory >= 0
                stats.record_data_point memory
              else 
                NewRelic::Agent.instance.log.error "Error attempting to determine resident memory for pid #{process} (got result of #{memory}, this process = #{$$}).  Disabling this metric."
                NewRelic::Agent.instance.log.error "Faulty command: `#{@ps}`"
                @broken = true
              end
            rescue Exception => e
              if e.is_a? Errno::ENOMEM
                NewRelic::Agent.instance.log.error "Got OOM trying to determine process memory usage"
              else
                raise e
              end
            end
          end
        end
      end
    end
  end
end

NewRelic::Agent::MemorySampler.new
