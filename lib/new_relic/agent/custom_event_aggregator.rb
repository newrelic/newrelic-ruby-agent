# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/sized_buffer'

module NewRelic
  module Agent
    class CustomEventAggregator
      include NewRelic::Coerce

      # Because DEFAULT_TYPE is a symbol, it cannot have name clashes
      # with user-defined types, all of which are strings.
      DEFAULT_TYPE     = :default_type
      DEFAULT_CAPACITY = 1000
      TYPE             = 'type'.freeze
      TIMESTAMP        = 'timestamp'.freeze

      def initialize
        @lock    = Mutex.new
        @buffers = {
          DEFAULT_TYPE => SizedBuffer.new(DEFAULT_CAPACITY)
        }
        @type_strings = Hash.new { |hash, key| hash[key] = key.to_s.freeze }
      end

      def register_event_type(type, capacity)
        type = @type_strings[type]
        @lock.synchronize do
          if @buffers[type]
            NewRelic::Agent.logger.warn("Ignoring attempt to re-register custom event type '#{type}'.")
            return
          end
          @buffers[type] = SizedBuffer.new(capacity)
        end
        NewRelic::Agent.logger.debug("Registered custom event buffer of type '#{type}' with capacity #{capacity}")
      end

      def record(type, attributes)
        type = @type_strings[type]
        event = [
          { TYPE => type, TIMESTAMP => Time.now.to_i },
          attributes
        ]
        event.map! { |h| event_params!(h, 'recording custom event') }

        stored = @lock.synchronize do
          append_event_locked(type, event)
        end
        stored
      end

      def harvest!
        results = []
        drop_count = 0
        @lock.synchronize do
          @buffers.each do |type, buffer|
            results.concat(buffer.to_a)
            drop_count += buffer.dropped
            buffer.reset!
          end
        end
        note_dropped_events(results.size, drop_count)
        results
      end

      def note_dropped_events(captured_count, dropped_count)
        if dropped_count > 0
          total_count = captured_count + dropped_count
          NewRelic::Agent.logger.warn("Dropped #{dropped_count} events out of #{total_count}.")
        end
      end

      def merge!(samples)
        @lock.synchronize do
          samples.each do |sample|
            append_event_locked(sample[0][TYPE], sample)
          end
        end
      end

      def reset!
        @lock.synchronize do
          @buffers.each_value(&:reset!)
        end
      end

      # This should only be called with @lock held
      def append_event_locked(type, event)
        if @buffers[type]
          @buffers[type].append(event)
        else
          @buffers[DEFAULT_TYPE].append(event)
        end
      end
    end
  end
end