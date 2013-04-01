# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require 'new_relic/agent/instrumentation/evented_subscriber'
require 'rack'

module NewRelic
  module Agent
    module Instrumentation
      class ActionControllerSubscriber < EventedSubscriber
        def initialize
          super
          NewRelic::Agent.instance.events.subscribe(:before_call) do |env|
            TransactionInfo.reset(::Rack::Request.new(env))
          end
        end

        def start(name, id, payload)
          payload[:request] = TransactionInfo.get.request
          event = ControllerEvent.new(name, Time.now, nil, id, payload)
          push_event(event)

          if NewRelic::Agent.is_execution_traced? && !event.ignored?
            start_transaction(event)
          else
            # if this transaction is ignored, make sure child
            # transaction are also ignored
            NewRelic::Agent.instance.push_trace_execution_flag(false)
          end
        end

        def finish(name, id, payload)
          event = pop_event(id)
          event.payload.merge!(payload)

          set_enduser_ignore if event.enduser_ignored?

          if NewRelic::Agent.is_execution_traced? && !event.ignored?
            record_queue_time(event)
            record_metrics(event)
            record_apdex(event)
            record_instance_busy(event)
            stop_transaction(event)
          else
            Agent.instance.pop_trace_execution_flag
          end
        end

        def set_enduser_ignore
          TransactionInfo.get.ignore_end_user = true
        end

        def record_metrics(event)
          controller_metric = MetricSpec.new(event.metric_name)
          metric_frame = Instrumentation::MetricFrame.current
          metrics = [ 'HttpDispatcher']
          if metric_frame.has_parent?
            controller_metric.scope = StatsEngine::MetricStats::SCOPE_PLACEHOLDER
            record_metric_on_parent_transaction(controller_metric, event.duration)
          end
          metrics << controller_metric.dup

          Agent.instance.stats_engine.record_metrics(metrics, event.duration)
        end

        def record_metric_on_parent_transaction(metric, time)
          Agent.instance.stats_engine.transaction_stats_stack[-2] \
            .record(metric, time)
        end

        def record_apdex(event)
          return if event.apdex_ignored?
          metric_parser = MetricParser::MetricParser \
            .for_metric_named(event.metric_name)
          duration_plus_queue_time = event.end - (event.queue_start || event.time)
          MetricFrame.record_apdex(metric_parser,
                                   event.duration,
                                   duration_plus_queue_time,
                                   event.exception_encountered?)
        end

        def record_instance_busy(event)
          BusyCalculator.dispatcher_start(event.time)
          BusyCalculator.dispatcher_finish(event.end)
        end

        def record_queue_time(event)
          return unless event.queue_start
          QueueTime.record_frontend_metrics(event.queue_start, event.time)
        end

        def start_transaction(event)
          # RUBY-1059 we want to get rid of this
          TransactionInfo.get.transaction_name = event.metric_name
          frame_data = Instrumentation::MetricFrame.current(true)
          frame_data.request = event.payload[:request]
          frame_data.filtered_params = filter(event.payload[:params])
          frame_data.push(event.metric_name)
          frame_data.apdex_start = (event.queue_start || event.time)
          frame_data.start_transaction
          event.scope = Agent.instance.stats_engine \
            .push_scope(:action_controller, event.time)
        end

        def stop_transaction(event)
          TransactionInfo.get.transaction_name = event.metric_name
          Agent.instance.stats_engine \
            .pop_scope(event.scope, event.metric_name, event.end)
          frame_data = Instrumentation::MetricFrame.current
          frame_data.pop(event.metric_name)
        end

        def filter(params)
          filters = Rails.application.config.filter_parameters
          ActionDispatch::Http::ParameterFilter.new(filters).filter(params)
        end
      end

      class ControllerEvent < Event
        attr_accessor :parent, :scope
        attr_reader :queue_start

        def initialize(name, start, ending, transaction_id, payload)
          super

          @controller_class = payload[:controller].split('::') \
            .inject(Object){|m,o| m.const_get(o)}

          if payload[:request] && payload[:request].respond_to?(:env)
            @queue_start = QueueTime.parse_frontend_timestamp(payload[:request].env, self.time)
          end
        end

        def metric_name
          name = "Controller/#{metric_path}/#{metric_action}"
          @final_name ||= Agent.instance.transaction_rules.rename(name)
          return @final_name
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
