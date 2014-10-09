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
        named :delayed_job

        def initialize
          raise Unsupported, "DJ instrumentation disabled" if Agent.config[:disable_dj]
          raise Unsupported, "No DJ worker present" unless NewRelic::DelayedJobInjection.worker_name
        end

        def record_failed_jobs(value)
          NewRelic::Agent.record_metric("Workers/DelayedJob/failed_jobs", value)
        end

        def record_locked_jobs(value)
          NewRelic::Agent.record_metric("Workers/DelayedJob/locked_jobs", value)
        end

        FAILED_QUERY = 'failed_at is not NULL'.freeze
        LOCKED_QUERY = 'locked_by is not NULL'.freeze

        def failed_jobs
          count(FAILED_QUERY)
        end

        def locked_jobs
          count(LOCKED_QUERY)
        end

        def count(query)
          if ActiveRecord::VERSION::MAJOR.to_i < 4
            Delayed::Job.count(query)
          else
            Delayed::Job.where(query).count
          end
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
          queue_counts(column).each do |column_val, count|
            all_count += count
            metric = "Workers/DelayedJob/queue_length/#{column == 'queue' ? 'name' : column}/#{column_val}"
            NewRelic::Agent.record_metric(metric, count)
          end

          all_metric = "Workers/DelayedJob/queue_length/all"
          NewRelic::Agent.record_metric(all_metric, all_count)
        end

        QUEUE_QUERY_CONDITION = 'run_at < ? and failed_at is NULL'.freeze

        def queue_counts(column)
          # There is not an ActiveRecord syntax for what we're trying to do
          # here that's valid on 2.x through 4.1, so split it up.
          result = if ActiveRecord::VERSION::MAJOR.to_i < 4
            Delayed::Job.count(:group => column,
                               :conditions => [QUEUE_QUERY_CONDITION, Time.now])
          else
            Delayed::Job.where(QUEUE_QUERY_CONDITION, Time.now).
                         group(column).
                         count
          end
          result.to_a
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
