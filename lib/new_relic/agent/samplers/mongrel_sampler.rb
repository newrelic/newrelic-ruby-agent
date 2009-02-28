# NewRelic Instrumentation for Mongrel - tracks the queue length of the mongrel server
module NewRelic::Agent::Samplers
  class MongrelSampler < NewRelic::Agent::Sampler
    def initialize mongrel_instance
      super :mongrel
      @mongrel = mongrel_instance
    end
    def queue_stats
      @queue_stats ||= stats_engine.get_stats("Mongrel/Queue Length", false)
    end
    def poll
      if @mongrel
        qsize = @mongrel.workers.list.length
        qsize -= 1 if NewRelic::Agent::Instrumentation::DispatcherInstrumentation::BusyCalculator.is_busy?
        qsize = 0 if qsize < 0
        queue_stats.record_data_point qsize
      end
    end
  end
end