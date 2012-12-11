require 'new_relic/agent/sampler'
require 'new_relic/delayed_job_injection'

module NewRelic
  module Agent
    module Samplers
      # This sampler records the status of your delayed job table once a minute.
      # It assumes jobs are cleared after being run, and failed jobs are not (otherwise
      # the failed job metric is useless).
      #
      # In earlier versions it will break out the queue length by priority.  In later
      # versions of DJ where distinct queues are supported, it breaks it out by queue name.
      #
      class DelayedJobSampler < NewRelic::Agent::Sampler
        def initialize
          super :delayed_job_queue
          raise Unsupported, "DJ instrumentation disabled" if Agent.config[:disable_dj]
          raise Unsupported, "No DJ worker present" unless NewRelic::DelayedJobInjection.worker_name
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
          record error_stats, failed_jobs
          record locked_job_stats, locked_jobs

          if @queue
            record_queue_length_across_dimension('queue')
          else
            record_queue_length_across_dimension('priority')
          end
        end

        private

        def record_queue_length_across_dimension(column)
          all_count = 0
          Delayed::Job.count(:group => column, :conditions => ['run_at < ? and failed_at is NULL', Time.now]).each do | column_val, count |
            all_count += count
            record stats_engine.get_stats("Workers/DelayedJob/queue_length/#{column == 'queue' ? 'name' : column}/#{column_val}", false), count
          end
          record(stats_engine.get_stats("Workers/DelayedJob/queue_length/all", false), all_count)
        end

        # Figure out if we get the queues.
        def setup
          return unless @queue.nil?
          @setup = true
          columns = Delayed::Job.columns
          columns.each do | c |
            @queue = true if c.name.to_s == 'priority'
          end
          @queue ||= false
        end

        def record(stat, size)
          stat.record_data_point size
        end
      end
    end
  end
end
