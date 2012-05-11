require 'new_relic/agent/sampler'
require 'new_relic/delayed_job_injection'

module NewRelic
  module Agent
    module Samplers
      class DelayedJobSampler < NewRelic::Agent::Sampler
        def initialize
          super :delayed_job_queue
          raise Unsupported, "DJ instrumentation disabled" if NewRelic::Control.instance['disable_dj']
          raise Unsupported, "No DJ worker present" unless NewRelic::DelayedJobInjection.worker_name
        end

        def queue_stats
          stats_engine.get_stats("Workers/DelayedJob/queue_length", false)
        end
        def error_stats
          stats_engine.get_stats("Workers/DelayedJob/failed_jobs", false)
        end
        def locked_job_stats
          stats_engine.get_stats("Workers/DelayedJob/locked_jobs", false)
        end

        def local_env
          NewRelic::Control.instance.local_env
        end

        def worker_name
          local_env.dispatcher_instance_id
        end

        def queued_jobs
          Delayed::Job.count(:conditions => ['run_at < ? and failed_at is NULL', Time.now])
        end
        def failed_jobs
          Delayed::Job.count(:conditions => 'failed_at is not NULL')
        end
        def locked_jobs
          Delayed::Job.count(:conditions => 'locked_by is not NULL')
        end

        def self.supported_on_this_platform?
          defined?(Delayed::Job)
        end

        def poll
          record queue_stats, queued_jobs
          record error_stats, failed_jobs
          record locked_job_stats, locked_jobs
        end

        private
        def record(stat, size)
          stat.record_data_point size
        end
      end
    end
  end
end
