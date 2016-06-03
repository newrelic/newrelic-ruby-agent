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
          state = NewRelic::Agent::TransactionState.tl_get
          return unless state.is_execution_traced?
          event = super
          if event.name == PERFORM_ACTION
            start_transaction state, event
          else
            start_recording_metrics state, event
          end
        rescue => e
          log_notification_error e, name, 'start'
        end

        def finish name, id, payload #THREAD_LOCAL_ACCESS
          state = NewRelic::Agent::TransactionState.tl_get
          return unless state.is_execution_traced?
          event = super
          notice_error payload if payload.key? :exception
          if event.name == PERFORM_ACTION
            finish_transaction state
          else
            stop_recording_metrics state, event
          end
        rescue => e
          log_notification_error e, name, 'finish'
        end

        private

        def start_transaction state, event
          Transaction.start(state, :action_cable, :transaction_name => transaction_name_from_event(event))
        end

        def finish_transaction state
          Transaction.stop(state)
        end

        def start_recording_metrics state, event
          expected_scope = MethodTracerHelpers::trace_execution_scoped_header(state, event.time.to_f)
          event.payload[:expected_scope] =  expected_scope
        end

        def stop_recording_metrics state, event
          expected_scope = event.payload.delete :expected_scope
          metric_name = metric_name_from_event event
          MethodTracerHelpers::trace_execution_scoped_footer(state, event.time.to_f, metric_name, [], expected_scope, {:metric => true}, event.end.to_f)
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
    end
  end
end
