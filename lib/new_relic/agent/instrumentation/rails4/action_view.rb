# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Instrumentation
      class ActionViewSubscriber
        def initialize
          @event_stack = Hash.new {|h,id| h[id] = [] }
        end

        def self.subscribed?
          ActiveSupport::Notifications.notifier.listeners_for(/^render_.+\.action_view$/) \
            .find{|l| l.instance_variable_get(:@delegate).class == self }
        end

        def start(name, id, payload)
          event = ActiveSupport::Notifications::Event.new(name, Time.now, nil, id, payload)
          event.payload[:metric_name] = metric_name(event)
          parent = @event_stack[id].last
          parent << event if parent
          @event_stack[id].push event

          if NewRelic::Agent.is_execution_traced?
            event.payload[:scope] = NewRelic::Agent.instance.stats_engine \
              .push_scope(event.payload[:metric_name], event.time)
          end
        end

        def finish(name, id, payload)
          event = @event_stack[id].pop
          event.end = Time.now

          if NewRelic::Agent.is_execution_traced?
            record_metrics(event)
            NewRelic::Agent.instance.stats_engine \
              .pop_scope(event.payload[:scope], event.duration, event.end)
          end
        end

        def record_metrics(event)
          NewRelic::Agent.record_metric(event.payload[:metric_name], event.duration / 1000.0)
        end

        def metric_name(event)
          metric_path = event.payload[:identifier].split('/')[-2..-1].join('/')
          metric_action = case event.name
            when 'render_template.action_view'   then 'Rendering'
            when 'render_partial.action_view'    then 'Partial'
            when 'render_collection.action_view' then 'Partial'
          end
          "View/#{metric_path}/#{metric_action}"
        end
      end
    end
  end
end

DependencyDetection.defer do
  @name = :rails4_view

  depends_on do
    defined?(::Rails) && ::Rails::VERSION::MAJOR.to_i == 4
  end

  depends_on do
    !NewRelic::Agent.config[:disable_view_instrumentation]
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Rails 4 view instrumentation'
  end

  executes do
    if !NewRelic::Agent::Instrumentation::ActionViewSubscriber.subscribed?
      ActiveSupport::Notifications.subscribe(/^render_.+\.action_view$/,
        NewRelic::Agent::Instrumentation::ActionViewSubscriber.new)
    end
  end
end
