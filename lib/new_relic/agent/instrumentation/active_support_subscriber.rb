# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'notifications_subscriber'

module NewRelic
  module Agent
    module Instrumentation
      class ActiveSupportSubscriber < NotificationsSubscriber
        EVENT_NAME_TO_METHOD_NAME = {
          'cache_fetch_hit.active_support' => 'fetch_hit',
          'cache_generate.active_support' => 'generate',
          'cache_read.active_support' => 'read',
          'cache_write.active_support' => 'write',
          'cache_delete.active_support' => 'delete',
          'cache_exist?.active_support' => 'exist?',
          'cache_read_multi.active_support' => 'read_multi',
          'cache_write_multi.active_support' => 'write_multi',
          'cache_delete_multi.active_support' => 'delete_multi',
          'cache_delete_matched.active_support' => 'delete_matched',
          'cache_cleanup.active_support' => 'cleanup',
          'cache_increment.active_support' => 'increment',
          'cache_decrement.active_support' => 'decrement',
          'cache_prune.active_support' => 'prune',
          'message_serializer_fallback.active_support' => 'message_serializer_fallback'
        }.freeze

        def add_segment_params(segment, payload)
          segment.params[:key] = payload[:key]
          segment.params[:store] = payload[:store]
          segment.params[:hit] = payload[:hit] if payload.key?(:hit)
          segment.params[:super_operation] = payload[:super_operation] if payload.key?(:super_operation)
          segment
        end

        def metric_name(name, payload)
          store = payload[:store]
          method = method_name(name)
          "Ruby/ActiveSupport#{"/#{store}" if store}/#{method}"
        end

        def method_name(name)
          EVENT_NAME_TO_METHOD_NAME.fetch(name, name.delete_prefix('cache_').delete_suffix('.active_support'))
        end
      end
    end
  end
end
