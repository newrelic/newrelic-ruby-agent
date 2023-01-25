# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'new_relic/agent/instrumentation/notifications_subscriber'

module NewRelic
  module Agent
    module Instrumentation
      class ActiveJobSubscriber < NotificationsSubscriber
        PAYLOAD_KEYS = %i[adapter db_runtime error job wait]

        def start_segment(name, id, payload)
          segment = Tracer.start_segment(name: metric_name(name, payload))

          PAYLOAD_KEYS.each do |key|
            segment.params[key] = payload[key] if payload.key?(key)
          end

          push_segment(id, segment)
        end

        def finish_segment(id, payload)
          if segment = pop_segment(id)
            if exception = exception_object(payload)
              segment.notice_error(exception)
            end
            segment.finish
          end
        end

        def metric_name(name, payload)
          queue = payload[:job].queue_name
          method = method_from_name(name)
          "Ruby/ActiveJob/#{queue}/#{method}"
        end

        PATTERN = /\A([^\.]+)\.active_job\z/
        UNKNOWN = 'unknown'.freeze

        METHOD_NAME_MAPPING = Hash.new do |h, k|
          if PATTERN =~ k
            h[k] = $1
          else
            h[k] = UNKNOWN
          end
        end

        def method_from_name(name)
          METHOD_NAME_MAPPING[name]
        end
      end
    end
  end
end
