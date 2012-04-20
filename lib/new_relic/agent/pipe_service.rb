module NewRelic
  module Agent
    class PipeService

    	attr_reader :channel_id

    	def initialize(channel_id)
    		@channel_id = channel_id
    	end

    	def connect(config)
    		nil
    	end

    	def shutdown(time)
    		NewRelic::Agent::PipeChannelManager.channels[@channel_id].in.close
    	end

    	def metric_data(last_harvest_time, now, unsent_timeslice_data)
    		NewRelic::Agent::PipeChannelManager.channels[@channel_id].in.write(Marshal.dump(unsent_timeslice_data))
    	end
    end
  end
end
