# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'new_relic/agent/instrumentation/notifications_subscriber'

module NewRelic
  module Agent
    module Instrumentation
      class ActionCableSubscriber < NotificationsSubscriber
        PERFORM_ACTION = 'perform_action.action_cable'.freeze

        def start_segment(name, id, payload) # THREAD_LOCAL_ACCESS
          finishable = if name == PERFORM_ACTION
            Tracer.start_transaction_or_segment(
              name: transaction_name_from_payload(payload),
              category: :action_cable
            )
          else
            segment = Tracer.start_segment(name: metric_name_from_payload(name, payload))
            add_broadcasting_attribute(segment, payload)
            segment
          end

          push_segment(id, finishable)
        end

        private

        def transaction_name_from_payload(payload)
          "Controller/ActionCable/#{payload[:channel_class]}/#{payload[:action]}"
        end

        def metric_name_from_payload(name, payload)
          "Ruby/ActionCable/#{metric_name(payload)}#{action_name(name)}"
        end

        def metric_name(payload)
          # The trailing / is added in the metric_name method to protect against
          # double / characters in the name because there are some cases where
          # metric_name will return nil
          if NewRelic::Agent.config[:simplify_action_cable_broadcast_metrics]
            "#{payload[:channel_class]}/" if payload[:channel_class]
          else
            (payload[:broadcasting] || payload[:channel_class]) + '/'
          end
        end

        def add_broadcasting_attribute(segment, payload)
          return unless NewRelic::Agent.config[:simplify_action_cable_broadcast_metrics]
          return unless payload.key?(:broadcasting)

          segment.transaction.add_agent_attribute(
            'broadcasting',
            payload[:broadcasting],
            AttributeFilter::DST_SPAN_EVENTS
          )
        end

        DOT_ACTION_CABLE = '.action_cable'.freeze

        def action_name(name)
          name.gsub(DOT_ACTION_CABLE, NewRelic::EMPTY_STR)
        end
      end
    end
  end
end
