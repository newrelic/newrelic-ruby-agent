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

        def push_event(event)
          parent = event_stack[event.transaction_id].last
          event.parent = parent
          parent << event if parent
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
    end
  end
end
