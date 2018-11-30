# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require 'new_relic/agent/instrumentation/evented_subscriber'

module NewRelic
  module Agent
    module Instrumentation
      class ActiveStorageSubscriber < EventedSubscriber
        def start name, id, payload
          return unless state.is_execution_traced?
          start_recording_metrics(name, payload)
        rescue => e
          log_notification_error e, name, 'start'
        end

        def finish name, id, payload
          return unless state.is_execution_traced?
          stop_recording_metrics @segment
        end

        def start_recording_metrics name, payload
          NewRelic::Agent.logger.debug "Recorded segment with name: #{metric_name(name, payload)}"
          @segment = Transaction.start_segment name: metric_name(name, payload)
        end

        def stop_recording_metrics segment
          @segment.finish if @segment
        end

        def metric_name name, payload
          service = payload[:service]
          method = method_from_name name
          "Ruby/ActiveStorage/#{service}/#{method}"
        end

        DOT_ACTIVE_STORAGE = ".active_storage".freeze
        EMPTY_STRING = "".freeze

        def method_from_name name
          name.gsub DOT_ACTIVE_STORAGE, EMPTY_STRING
        end
      end
    end
  end
end
