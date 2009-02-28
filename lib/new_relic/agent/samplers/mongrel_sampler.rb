# NewRelic Instrumentation for Mongrel - tracks the queue length of the mongrel server
module NewRelic::Agent::Samplers
  class MongrelSampler < NewRelic::Agent::Sampler
    def initialize mongrel_instance
      super :mongrel
      @mongrel = mongrel_instance
    end
    
    def poll
      if @mongrel
        @queue_stat ||= stats_engine.get_stats("Mongrel/Queue Length", false)
        qsize = @mongrel.workers.list.length
        qsize -= 1 if NewRelic::Agent::Instrumentation::DispatcherInstrumentation::BusyCalculator.is_busy?
        qsize = 0 if qsize < 0
        @queue_stat.record_data_point qsize
      end
    end
  end
end