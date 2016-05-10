# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require 'new_relic/agent/instrumentation/evented_subscriber'

# Listen for ActiveSupport::Notifications events for ActionView render
# events.  Write metric data and transaction trace nodes for each event.
module NewRelic
  module Agent
    module Instrumentation
      class ActionViewSubscriber < EventedSubscriber
        def start(name, id, payload) #THREAD_LOCAL_ACCESS
          event = RenderEvent.new(name, Time.now, nil, id, payload)
          push_event(event)

          state = NewRelic::Agent::TransactionState.tl_get

          if state.is_execution_traced? && event.recordable?
            stack = state.traced_method_stack
            event.frame = stack.push_frame(state, :action_view, event.time)
          end
        rescue => e
          log_notification_error(e, name, 'start')
        end

        def finish(name, id, payload) #THREAD_LOCAL_ACCESS
          event = pop_event(id)

          state = NewRelic::Agent::TransactionState.tl_get

          if state.is_execution_traced? && event.recordable?
            stack = state.traced_method_stack
            frame = stack.pop_frame(state, event.frame, event.metric_name, event.end)
            record_metrics(event, frame)
          end
        rescue => e
          log_notification_error(e, name, 'finish')
        end

        def record_metrics(event, frame) #THREAD_LOCAL_ACCESS
          exclusive = event.duration - frame.children_time
          NewRelic::Agent.instance.stats_engine.tl_record_scoped_and_unscoped_metrics(
            event.metric_name, nil, event.duration, exclusive)
        end

        class RenderEvent < Event

          RENDER_TEMPLATE_EVENT_NAME   = 'render_template.action_view'.freeze
          RENDER_PARTIAL_EVENT_NAME    = 'render_partial.action_view'.freeze
          RENDER_COLLECTION_EVENT_NAME = 'render_collection.action_view'.freeze

          # Nearly every "render_blah.action_view" event has a child
          # in the form of "!render_blah.action_view".  The children
          # are the ones we want to record.  There are a couple
          # special cases of events without children.
          def recordable?
            name[0] == '!' ||
              metric_name == 'View/text template/Rendering' ||
              metric_name == "View/#{::NewRelic::Agent::UNKNOWN_METRIC}/Partial"
          end

          def metric_name
            if parent && (payload[:virtual_path] ||
                          (parent.payload[:identifier] =~ /template$/))
              return parent.metric_name
            elsif payload.key?(:virtual_path)
              identifier = payload[:virtual_path]
            else
              identifier = payload[:identifier]
            end

            # memoize
            @metric_name ||= "View/#{metric_path(name, identifier)}/#{metric_action(name)}"
            @metric_name
          end

          def metric_path(name, identifier)
            # Rails 5 sets identifier to nil for empty collections,
            # so do not mistake rendering a collection for rendering a file.
            if identifier == nil && name != RENDER_COLLECTION_EVENT_NAME
              'file'
            elsif identifier =~ /template$/
              identifier
            elsif identifier && (parts = identifier.split('/')).size > 1
              parts[-2..-1].join('/')
            else
              ::NewRelic::Agent::UNKNOWN_METRIC
            end
          end

          def metric_action(name)
            case name
            when /#{RENDER_TEMPLATE_EVENT_NAME}$/ then 'Rendering'
            when RENDER_PARTIAL_EVENT_NAME        then 'Partial'
            when RENDER_COLLECTION_EVENT_NAME     then 'Partial'
            end
          end
        end
      end
    end
  end
end
