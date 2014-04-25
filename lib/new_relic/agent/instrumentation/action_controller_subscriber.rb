# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require 'new_relic/agent/instrumentation/evented_subscriber'

module NewRelic
  module Agent
    module Instrumentation
      class ActionControllerSubscriber < EventedSubscriber
        def initialize
          super
          NewRelic::Agent.instance.events.subscribe(:before_call) do |env|

            request = begin
                        require 'rack'
                        ::Rack::Request.new(env)
                      rescue => e
                        Agent.logger.debug("Error creating Rack::Request object: #{e}")
                        nil
                      end
            TransactionState.request = request
          end
        end

        def start(name, id, payload)
          request = TransactionState.get.request
          event = ControllerEvent.new(name, Time.now, nil, id, payload, request)
          push_event(event)

          if NewRelic::Agent.is_execution_traced? && !event.ignored?
            start_transaction(event)
          else
            # if this transaction is ignored, make sure child
            # transaction are also ignored
            NewRelic::Agent.instance.push_trace_execution_flag(false)
          end
        rescue => e
          log_notification_error(e, name, 'start')
        end

        def finish(name, id, payload)
          event = pop_event(id)
          event.payload.merge!(payload)

          if NewRelic::Agent.is_execution_traced? && !event.ignored?
            stop_transaction(event)
          else
            Agent.instance.pop_trace_execution_flag
          end
        rescue => e
          log_notification_error(e, name, 'finish')
        end

        def start_transaction(event)
          Transaction.start(:controller,
                            :request          => event.request,
                            :filtered_params  => filter(event.payload[:params]),
                            :apdex_start_time => event.queue_start,
                            :transaction_name => event.metric_name)
        end

        def stop_transaction(event)
          Transaction.stop(Time.now,
                           :exception_encountered => event.exception_encountered?,
                           :ignore_apdex          => event.apdex_ignored?,
                           :ignore_enduser        => event.enduser_ignored?)
        end

        def filter(params)
          filters = Rails.application.config.filter_parameters
          ActionDispatch::Http::ParameterFilter.new(filters).filter(params)
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
          _is_filtered?('do_not_trace')
        end

        def apdex_ignored?
          _is_filtered?('ignore_apdex')
        end

        def enduser_ignored?
          _is_filtered?('ignore_enduser')
        end

        def exception_encountered?
          payload[:exception]
        end

        # FIXME: shamelessly ripped from ControllerInstrumentation
        def _is_filtered?(key)
          if @controller_class.respond_to? :newrelic_read_attr
            ignore_actions = @controller_class.newrelic_read_attr(key)
          end

          case ignore_actions
          when nil; false
          when Hash
            only_actions = Array(ignore_actions[:only])
            except_actions = Array(ignore_actions[:except])
            only_actions.include?(metric_action.to_sym) || (except_actions.any? && !except_actions.include?(metric_action.to_sym))
          else
            true
          end
        end

        def to_s
          "#<NewRelic::Agent::Instrumentation::ControllerEvent:#{object_id} name: \"#{name}\" id: #{transaction_id} payload: #{payload}}>"
        end
      end
    end
  end
end
