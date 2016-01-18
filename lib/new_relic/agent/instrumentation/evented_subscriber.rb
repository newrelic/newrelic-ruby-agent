# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Instrumentation
      class EventedSubscriber
        def initialize
          @queue_key = ['NewRelic', self.class.name, object_id].join('-')
        end

        def self.subscribed?
          # TODO: need to talk to Rails core about an API for this,
          # rather than digging through Listener ivars
          ActiveSupport::Notifications.notifier.instance_variable_get(:@subscribers) \
            .find{|s| s.instance_variable_get(:@delegate).class == self }
        end

        def self.subscribe(pattern)
          if !subscribed?
            ActiveSupport::Notifications.subscribe(pattern, new)
          end
        end

        def start(name, id, payload)
          event = ActiveSupport::Notifications::Event.new(name, Time.now, nil, id, payload)
          push_event(event)
          return event
        end

        def finish(name, id, payload)
          pop_event(id)
        end

        def log_notification_error(error, name, event_type)
          # These are important enough failures that we want the backtraces
          # logged at error level, hence the explicit log_exception call.
          NewRelic::Agent.logger.error("Error during #{event_type} callback for event '#{name}':")
          NewRelic::Agent.logger.log_exception(:error, error)
        end

        def push_event(event)
          parent = event_stack[event.transaction_id].last
          if parent && event.respond_to?(:parent=)
            event.parent = parent
            parent << event
          end
          event_stack[event.transaction_id].push event
        end

        def pop_event(transaction_id)
          event = event_stack[transaction_id].pop
          event.end = Time.now
          return event
        end

        def event_stack
          Thread.current[@queue_key] ||= Hash.new {|h,id| h[id] = [] }
        end
      end

      # Taken from ActiveSupport::Notifications::Event, pasted here
      # with a couple minor additions so we don't have a hard
      # dependency on ActiveSupport::Notifications.
      #
      # Represents an instrumentation event, provides timing and metric
      # name information useful when recording metrics.
      class Event
        attr_reader :name, :time, :transaction_id, :payload, :children
        attr_accessor :end, :parent, :frame

        def initialize(name, start, ending, transaction_id, payload)
          @name           = name
          @payload        = payload.dup
          @time           = start
          @transaction_id = transaction_id
          @end            = ending
          @children       = []
        end

        def metric_name
          raise NotImplementedError
        end

        def duration
          self.end - time
        end

        def <<(event)
          @children << event
        end

        def parent_of?(event)
          @children.include? event
        end
      end
    end
  end
end
