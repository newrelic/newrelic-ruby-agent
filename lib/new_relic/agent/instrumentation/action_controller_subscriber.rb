# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require 'new_relic/agent/instrumentation/evented_subscriber'
require 'new_relic/agent/instrumentation/ignore_actions'
require 'new_relic/agent/parameter_filtering'

module NewRelic
  module Agent
    module Instrumentation
      class ActionControllerSubscriber < EventedSubscriber

        def start(name, id, payload) #THREAD_LOCAL_ACCESS
          state = TransactionState.tl_get
          request = state.request
          event = ControllerEvent.new(name, Time.now, nil, id, payload, request)
          push_event(event)

          if state.is_execution_traced? && !event.ignored?
            start_transaction(state, event)
          else
            # if this transaction is ignored, make sure child
            # transaction are also ignored
            state.current_transaction.ignore! if state.current_transaction
            NewRelic::Agent.instance.push_trace_execution_flag(false)
          end
        rescue => e
          log_notification_error(e, name, 'start')
        end

        def finish(name, id, payload) #THREAD_LOCAL_ACCESS
          event = pop_event(id)
          event.payload.merge!(payload)

          state = TransactionState.tl_get

          if state.is_execution_traced? && !event.ignored?
            stop_transaction(state, event)
          else
            Agent.instance.pop_trace_execution_flag
          end
        rescue => e
          log_notification_error(e, name, 'finish')
        end

        def start_transaction(state, event)
          Transaction.start(state, :controller,
                            :request          => event.request,
                            :filtered_params  => filter(event.payload[:params]),
                            :apdex_start_time => event.queue_start,
                            :transaction_name => event.metric_name)
        end

        def stop_transaction(state, event)
          txn = state.current_transaction
          txn.ignore_apdex!   if event.apdex_ignored?
          txn.ignore_enduser! if event.enduser_ignored?
          Transaction.stop(state)
        end

        def filter(params)
          munged_params = NewRelic::Agent::ParameterFiltering.filter_rails_request_parameters(params)
          filters = Rails.application.config.filter_parameters
          ActionDispatch::Http::ParameterFilter.new(filters).filter(munged_params)
        end
      end

      class ControllerEvent < Event
        attr_accessor :parent
        attr_reader :queue_start, :request

        def initialize(name, start, ending, transaction_id, payload, request)
          # We have a different initialize parameter list, so be explicit
          super(name, start, ending, transaction_id, payload)

          @request = request
          @controller_class = payload[:controller].split('::') \
            .inject(Object){|m,o| m.const_get(o)}

          if request && request.respond_to?(:env)
            @queue_start = QueueTime.parse_frontend_timestamp(request.env, self.time)
          end
        end

        def metric_name
          @metric_name || "Controller/#{metric_path}/#{metric_action}"
        end

        def metric_path
          @controller_class.controller_path
        end

        def metric_action
          payload[:action]
        end

        def ignored?
          _is_filtered?(ControllerInstrumentation::NR_DO_NOT_TRACE_KEY)
        end

        def apdex_ignored?
          _is_filtered?(ControllerInstrumentation::NR_IGNORE_APDEX_KEY)
        end

        def enduser_ignored?
          _is_filtered?(ControllerInstrumentation::NR_IGNORE_ENDUSER_KEY)
        end

        def _is_filtered?(key)
          NewRelic::Agent::Instrumentation::IgnoreActions.is_filtered?(
            key,
            @controller_class,
            metric_action)
        end

        def to_s
          "#<NewRelic::Agent::Instrumentation::ControllerEvent:#{object_id} name: \"#{name}\" id: #{transaction_id} payload: #{payload}}>"
        end
      end
    end
  end
end
