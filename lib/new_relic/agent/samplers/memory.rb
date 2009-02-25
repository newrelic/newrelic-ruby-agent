module NewRelic::Agent
  
  # PSSampler
  #
  # A class that samples memory by forking the "ps" command
  #
  class PSSampler
    def initialize(command)
      @broken = false
      @command = command
    end
    
    # Returns the amount of resident memory this process is using in MB
    #
    def get_memory_sample
      return nil if @broken
      
      process = $$
      memory = `#{@command} #{process}`.split("\n")[1].to_f / 1024.0 rescue 0

      # if for some reason the ps command doesn't work on the resident os,
      # then don't execute it any more.
      if memory > 0
        memory
      else 
        NewRelic::Agent.instance.log.error "Error attempting to determine resident memory for pid #{process} (got result of #{memory}, this process = #{$$}).  Disabling this metric."
        NewRelic::Agent.instance.log.error "Faulty command: `#{command}`"
        @broken = true
        nil
      end
    end
  end

  
  # ProcStatusSampler
  #
  # A class that samples memory by reading the file /proc/$$/status, which is specific to linux
  #
  class ProcStatusSampler
    
    # This is called first to make sure the sampler can run on this host, otherwise a ps sampler is used
    #
    def can_run?
      get_memory_sample != 0.0 rescue nil
    end
    
    # Returns the amount of resident memory this process is using in MB
    #
    def get_memory_sample
      File.open("/proc/#{$$}/status", "r") do |f|
        while !f.eof? 
          if f.readline =~ /RSS:\s*(\d+) kB/i
            return $1.to_f / 1024.0
          end
        end
      end
      return 0.0
    end
  end
  
  
  # MemorySampler
  #
  # Master memory sampler class. Picks the correct sampler to use based on the environment
  # 
  class MemorySampler

    def initialize
      if RUBY_PLATFORM =~ /java/
        platform = %x[uname -s].downcase
      else
        platform = RUBY_PLATFORM.downcase
      end
      
      # macos, linux, solaris
      if platform =~ /linux/
        sampler = ProcStatusSampler.new
        unless sampler.can_run?
          NewRelic::Agent.instance.log.error "Error attempting to use /proc/$$/status file for reading memory. Using ps command instead"
          sampler = PSSampler.new("ps -o rsz")
        else
          NewRelic::Agent.instance.log.info "Using /proc/$$/status for reading process memory."
        end
      elsif platform =~ /darwin/
        sampler = PSSampler.new("ps -o rsz")
      elsif platform =~ /freebsd/
        sampler = PSSampler.new("ps -o rss")
      elsif platform =~ /solaris/
        sampler = PSSampler.new("/usr/bin/ps -o rss -p")
      else
        raise "Unsupported platform for getting memory: #{platform}"
      end
      
      NewRelic::Agent.instance.stats_engine.add_sampled_metric("Memory/Physical") do |stats|
        sample = sampler.get_memory_sample
        stats.record_data_point sample if sample
      end
      
    end
  end
end

NewRelic::Agent::MemorySampler.new
