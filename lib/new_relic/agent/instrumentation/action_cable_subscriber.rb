# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require 'new_relic/agent/instrumentation/evented_subscriber'

module NewRelic
  module Agent
    module Instrumentation
      class ActionCableSubscriber < EventedSubscriber

        PERFORM_ACTION = 'perform_action.action_cable'.freeze

        def start name, id, payload #THREAD_LOCAL_ACCESS
          return unless state.is_execution_traced?
          event = CableEvent.new(name, Time.now, nil, id, payload)
          push_event(event)
          event.segment = if event.name == PERFORM_ACTION
            start_transaction event
          else
            start_segment event
          end
        rescue => e
          log_notification_error e, name, 'start'
        end

        def finish name, id, payload #THREAD_LOCAL_ACCESS
          return unless state.is_execution_traced?
          event = super
          notice_error payload if payload.key? :exception
          event.segment.finish if event.segment
        rescue => e
          log_notification_error e, name, 'finish'
        end

        private

        def start_transaction event
          Transaction.start(state, :action_cable, :transaction_name => transaction_name_from_event(event))
        end

        def start_segment event
          Transaction.start_segment metric_name_from_event(event)
        end

        def transaction_name_from_event event
          "Controller/ActionCable/#{event.payload[:channel_class]}/#{event.payload[:action]}"
        end

        def metric_name_from_event event
          "Ruby/ActionCable/#{event.payload[:channel_class]}/#{action_name_from_event(event)}"
        end

        DOT_ACTION_CABLE = ".action_cable".freeze
        EMPTY_STRING = "".freeze

        def action_name_from_event event
          event.name.gsub DOT_ACTION_CABLE, EMPTY_STRING
        end

        def notice_error payload
          NewRelic::Agent.notice_error payload[:exception_object]
        end
      end

      class CableEvent < Event
        attr_accessor :segment
      end
    end
  end
end
