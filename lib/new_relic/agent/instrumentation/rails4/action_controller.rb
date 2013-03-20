# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require 'new_relic/agent/instrumentation/rails4/evented_subscriber'
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
            NewRelic::Agent.instance.push_trace_execution_flag(false)
          end
        end

        def finish(name, id, payload)
          event = super
          event.payload.merge!(payload)

          if NewRelic::Agent.is_execution_traced? && !event.ignored?
            record_queue_time(event)
            record_metrics(event)
            record_apdex(event)
            record_instance_busy(event)
            stop_transaction(event)
          else
            NewRelic::Agent.instance.pop_trace_execution_flag
          end
        end

        def record_metrics(event)
          controller_metric = NewRelic::MetricSpec.new(event.metric_name)
          metric_frame = NewRelic::Agent::Instrumentation::MetricFrame.current
          if metric_frame.parent_metric
            controller_metric.scope = metric_frame.parent_metric.name
          end
          metrics = [ controller_metric, 'HttpDispatcher' ]
          if event.exception_encountered?
            metrics << "Errors/#{event.metric_name}"
            metrics << "Errors/all"
          end

          NewRelic::Agent.instance.stats_engine.record_metrics(metrics,
                              event.duration_in_seconds)
        end

        def record_apdex(event)
          return if event.apdex_ignored?
          metric_parser = NewRelic::MetricParser::MetricParser \
            .for_metric_named(event.metric_name)
          MetricFrame.record_apdex(metric_parser,
                                   event.duration_in_seconds,
                                   event.duration_in_seconds,
                                   event.exception_encountered?)
        end

        def record_instance_busy(event)
          NewRelic::Agent::BusyCalculator.dispatcher_start(event.time)
          NewRelic::Agent::BusyCalculator.dispatcher_finish(event.end)
        end

        def record_queue_time(event)
          return unless event.payload[:request]
          queue_start = QueueTime.parse_frontend_timestamp(event.payload[:request].env,
                                                           event.time)
          QueueTime.record_frontend_metrics(queue_start, event.time) if queue_start
        end

        def start_transaction(event)
          frame_data = NewRelic::Agent::Instrumentation::MetricFrame.current(true)
          frame_data.filtered_params = {}
          frame_data.push(event.metric_name)
          frame_data.apdex_start = event.time
          NewRelic::Agent::TransactionInfo.get.transaction_name = event.metric_name
          frame_data.start_transaction
          event.scope = NewRelic::Agent.instance.stats_engine \
            .push_scope(event.metric_name, event.time)
        end

        def stop_transaction(event)
          frame_data = NewRelic::Agent::Instrumentation::MetricFrame.current
          frame_data.pop
          NewRelic::Agent.instance.stats_engine \
            .pop_scope(event.scope, event.duration, event.end)
        end
      end

      class ControllerEvent < ActiveSupport::Notifications::Event
        attr_accessor :parent, :scope

        def metric_name
          name = "Controller/#{metric_path}/#{metric_action}"
          @final_name ||= NewRelic::Agent.instance.transaction_rules.rename(name)
          return @final_name
        end

        def metric_path
          controller_class.controller_path
        end

        def metric_action
          payload[:action]
        end

        def controller_class
          @controller_class ||= payload[:controller].split('::') \
            .inject(Object){|m,o| m.const_get(o)}
          return @controller_class
        end

        def ignored?
          _is_filtered?('do_not_trace')
        end

        def apdex_ignored?
          _is_filtered?('ignore_apdex')
        end

        def enduser_ignored?
        end

        def exception_encountered?
          payload[:exception]
        end

        def duration_in_seconds
          Helper.milliseconds_to_seconds(duration)
        end

        # FIXME: shamelessly ripped from ControllerInstrumentation
        def _is_filtered?(key)
          if controller_class.respond_to? :newrelic_read_attr
            ignore_actions = controller_class.newrelic_read_attr(key)
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
      end if defined?(ActiveSupport::Notifications::Event)

      module Rails4
        module ActionController
          def self.newrelic_write_attr(attr_name, value) # :nodoc:
            write_inheritable_attribute(attr_name, value)
          end

          def self.newrelic_read_attr(attr_name) # :nodoc:
            read_inheritable_attribute(attr_name)
          end
        end
      end
    end
  end
end

DependencyDetection.defer do
  @name = :rails4_controller

  depends_on do
    defined?(::Rails) && ::Rails::VERSION::MAJOR.to_i == 4
  end

  depends_on do
    defined?(ActionController) && defined?(ActionController::Base)
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Rails 4 Controller instrumentation'
  end

  executes do
    class ActionController::Base
      include NewRelic::Agent::Instrumentation::ControllerInstrumentation
      include NewRelic::Agent::Instrumentation::Rails4::ActionController
    end
    NewRelic::Agent::Instrumentation::ActionControllerSubscriber \
      .subscribe(/^process_action.action_controller$/)
  end
end
