# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/sized_buffer'

module NewRelic
  module Agent
    class CustomEventAggregator
      include NewRelic::Coerce

      DEFAULT_TYPE     = '__default_type__'.freeze
      TYPE             = 'type'.freeze
      TIMESTAMP        = 'timestamp'.freeze
      EVENT_PARAMS_CTX = 'recording custom event'.freeze

      DEFAULT_CAPACITY_KEY = :'custom_insights_events.max_samples_stored'

      def initialize
        @lock    = Mutex.new
        @buffers = {}
        @type_strings = Hash.new { |hash, key| hash[key] = key.to_s.freeze }

        capacity = NewRelic::Agent.config[DEFAULT_CAPACITY_KEY]
        register_event_type(DEFAULT_TYPE, capacity, SizedBuffer)
        register_config_callbacks
      end

      def register_config_callbacks
        NewRelic::Agent.config.register_callback(DEFAULT_CAPACITY_KEY) do |max_samples|
          NewRelic::Agent.logger.debug "CustomEventAggregator max_samples set to #{max_samples}"
          @lock.synchronize do
            @buffers[DEFAULT_TYPE].capacity = max_samples
          end
        end
      end

      def register_event_type(type, capacity, buffer_class = SizedBuffer)
        type = @type_strings[type]
        @lock.synchronize do
          if @buffers[type]
            NewRelic::Agent.logger.warn("Ignoring attempt to re-register custom event type '#{type}'.")
            return
          end
          @buffers[type] = buffer_class.new(capacity)
        end
        NewRelic::Agent.logger.debug("Registered custom event buffer of type '#{type}' with capacity #{capacity}")
      end

      def record(type, attributes)
        type = @type_strings[type]
        event = [
          { TYPE => type, TIMESTAMP => Time.now.to_i },
          attributes
        ]
        event.each { |h| event_params!(h, EVENT_PARAMS_CTX) }

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
            drop_count += buffer.num_dropped
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
