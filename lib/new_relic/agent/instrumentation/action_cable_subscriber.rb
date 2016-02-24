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
          finish_transaction state
        rescue => e
          log_notification_error e, name, 'finish'
        end

        private

        CATEGORY = "Controller/ActionCable".freeze

        def start_transaction state, payload
          Transaction.start(state, CATEGORY, :transaction_name => name_from_payload(payload))
        end

        def finish_transaction state
          Transaction.stop(state)
        end

        def name_from_payload payload
          "#{CATEGORY}/#{payload[:channel_class]}/#{payload[:action]}"
        end
      end
    end
  end
end
