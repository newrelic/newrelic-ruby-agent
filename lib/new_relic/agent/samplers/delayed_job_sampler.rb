# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

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

        def record_failed_jobs(value)
          NewRelic::Agent.record_metric("Workers/DelayedJob/failed_jobs", value)
        end

        def record_locked_jobs(value)
          NewRelic::Agent.record_metric("Workers/DelayedJob/locked_jobs", value)
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
          record_failed_jobs(failed_jobs)
          record_locked_jobs(locked_jobs)

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
            metric = "Workers/DelayedJob/queue_length/#{column == 'queue' ? 'name' : column}/#{column_val}"
            NewRelic::Agent.record_metric(metric, count)
          end
          all_metric = "Workers/DelayedJob/queue_length/all"
          NewRelic::Agent.record_metric(all_metric, all_count)
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
      end
    end
  end
end
