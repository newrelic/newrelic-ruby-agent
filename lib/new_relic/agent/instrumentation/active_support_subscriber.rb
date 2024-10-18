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
          # TODO: OLD RUBIES - remove the <= 2.4 path once 2.5+ is required
          if RUBY_VERSION.to_f <= 2.4
            # String#delete_prefix requires Ruby 2.5+
            # rubocop:disable Performance/DeleteSuffix
            EVENT_NAME_TO_METHOD_NAME.fetch(name, name.sub(/\Acache_/, '').sub(/\.active_support\z/, ''))
            # rubocop:enable Performance/DeleteSuffix
          else
            EVENT_NAME_TO_METHOD_NAME.fetch(name, name.delete_prefix('cache_').delete_suffix('.active_support'))
          end
        end
      end
    end
  end
end
