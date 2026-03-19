# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'new_relic/agent/instrumentation/notifications_subscriber'

module NewRelic
  module Agent
    module Instrumentation
      class ActiveJobSubscriber < NotificationsSubscriber
        PAYLOAD_KEYS = %i[adapter db_runtime error job wait jobs step interrupted]

        def add_segment_params(segment, payload)
          PAYLOAD_KEYS.each do |key|
            segment.params[key] = payload[key] if payload.key?(key)
          end

          # Add step name for Rails 8.1+ Continuations (available at start)
          if payload[:step]&.respond_to?(:name)
            step = payload[:step]
            segment.params[:step_name] = step.name.to_s
            segment.params[:resumed] = step.resumed if step.respond_to?(:resumed)
          end
        end

        def finish_segment(id, payload)
          segment = pop_segment(id)
          return unless segment

          # Update step-specific attributes that are only available after step execution
          if payload[:step]&.respond_to?(:cursor)
            step = payload[:step]
            segment.params[:cursor] = step.cursor if step.cursor
          end

          if exception = exception_object(payload)
            segment.notice_error(exception)
          end
          segment.finish
        end

        # NOTE: For `enqueue_all.active_job`, only the first job is used to determine the queue.
        # Therefore, this assumes all jobs given as arguments for perform_all_later share the same queue.
        def metric_name(name, payload)
          job = payload[:job] || payload[:jobs].first

          queue = job.queue_name
          job_class = job.class.name.include?('::') ? job.class.name[job.class.name.rindex('::') + 2..-1] : job.class.name
          method = method_from_name(name)

          # Include step name for Rails 8.1+ Continuations
          if (method == 'step' || method == 'step_started') && payload[:step]&.respond_to?(:name)
            step_name = payload[:step].name
            "Ruby/ActiveJob/#{queue}/#{job_class}/#{method}/#{step_name}"
          else
            "Ruby/ActiveJob/#{queue}/#{job_class}/#{method}"
          end
        end

        PATTERN = /\A([^\.]+)\.active_job\z/

        METHOD_NAME_MAPPING = Hash.new do |h, k|
          if PATTERN =~ k
            h[k] = $1
          else
            h[k] = NewRelic::UNKNOWN
          end
        end

        def method_from_name(name)
          METHOD_NAME_MAPPING[name]
        end
      end
    end
  end
end
