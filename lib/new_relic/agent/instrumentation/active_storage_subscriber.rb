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
          start_segment(name, id, payload)
        rescue => e
          log_notification_error e, name, 'start'
        end

        def finish name, id, payload
          return unless state.is_execution_traced?

          finish_segment id
        end

        def start_segment name, id, payload
          segment = Transaction.start_segment name: metric_name(name, payload)
          segment.params[:key] = payload[:key]
          segment.params[:exist] = payload[:exist] if payload.key? :exist
          event_stack[id].push segment
        end

        def finish_segment id
          segment = event_stack[id].pop
          segment.finish if segment
        end

        def metric_name name, payload
          service = payload[:service]
          method = method_from_name name
          "Ruby/ActiveStorage/#{service}Service/#{method}"
        end

        METHOD_NAME_MAPPING = {
          "service_upload.active_storage"             => "upload".freeze,
          "service_streaming_download.active_storage" => "streaming_download".freeze,
          "service_download.active_storage"           => "download".freeze,
          "service_delete.active_storage"             => "delete".freeze,
          "service_delete_prefixed.active_storage"    => "delete_prefixed".freeze,
          "service_exist.active_storage"              => "exist".freeze,
          "service_url.active_storage"                => "url".freeze
        }

        def method_from_name name
          METHOD_NAME_MAPPING[name]
        end
      end
    end
  end
end
