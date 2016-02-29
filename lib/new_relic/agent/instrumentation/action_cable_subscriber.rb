# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require 'new_relic/agent/instrumentation/evented_subscriber'

module NewRelic
  module Agent
    module Instrumentation
      class ActionCableSubscriber < EventedSubscriber

        def start name, id, payload #THREAD_LOCAL_ACCESS
          state = NewRelic::Agent::TransactionState.tl_get
          return unless state.is_execution_traced?
          super
          start_transaction state, payload
        rescue => e
          log_notification_error e, name, 'start'
        end

        def finish name, id, payload #THREAD_LOCAL_ACCESS
          state = NewRelic::Agent::TransactionState.tl_get
          return unless state.is_execution_traced?
          super
          notice_error payload if payload.key? :exception
          finish_transaction state
        rescue => e
          log_notification_error e, name, 'finish'
        end

        private

        def start_transaction state, payload
          Transaction.start(state, :action_cable, :transaction_name => name_from_payload(payload))
        end

        def finish_transaction state
          Transaction.stop(state)
        end

        def name_from_payload payload
          "Controller/ActionCable/#{payload[:channel_class]}/#{payload[:action]}"
        end

        def notice_error payload
          NewRelic::Agent.notice_error payload[:exception_object]
        end
      end
    end
  end
end
