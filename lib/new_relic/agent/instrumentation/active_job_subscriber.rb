# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'new_relic/agent/instrumentation/notifications_subscriber'

module NewRelic
  module Agent
    module Instrumentation
      class ActiveJobSubscriber < NotificationsSubscriber
        PAYLOAD_KEYS = %i[adapter db_runtime error job wait jobs]

        def add_segment_params(segment, payload)
          PAYLOAD_KEYS.each do |key|
            segment.params[key] = payload[key] if payload.key?(key)
          end
        end

        # NOTE: For `enqueue_all.active_job`, only the first job is used to determine the queue.
        # Therefore, this assumes all jobs given as arguments for perform_all_later share the same queue.
        def metric_name(name, payload)
          job = payload[:job] || payload[:jobs].first

          queue = job.queue_name
          job_class = class_name.include?('::') ?
  class_name[class_name.rindex('::')+2..-1] : class_name
          method = method_from_name(name)
          "Ruby/ActiveJob/#{job_class}/#{queue}/#{method}"
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
