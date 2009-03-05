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
        # The mongrel workers list includes workers actively processing requests
        # so you need to subtract what appears to be the active workers from the total
        # number of workers to get the queue size.
        qsize = @mongrel.workers.list.length - NewRelic::Agent::Instrumentation::DispatcherInstrumentation::BusyCalculator.busy_count
        qsize = 0 if qsize < 0
        queue_stats.record_data_point qsize
      end
    end
  end
end