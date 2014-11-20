# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/sized_buffer'

module NewRelic
  module Agent
    class CustomEventAggregator
      include NewRelic::Coerce

      TYPE             = 'type'.freeze
      TIMESTAMP        = 'timestamp'.freeze
      EVENT_PARAMS_CTX = 'recording custom event'.freeze
      EVENT_TYPE_REGEX = /^[a-zA-Z0-9:_ ]+$/.freeze

      DEFAULT_CAPACITY_KEY = :'custom_insights_events.max_samples_stored'

      def initialize
        @lock         = Mutex.new
        @buffer       = SampledBuffer.new(NewRelic::Agent.config[DEFAULT_CAPACITY_KEY])
        @type_strings = Hash.new { |hash, key| hash[key] = key.to_s.freeze }
        register_config_callbacks
      end

      def register_config_callbacks
        NewRelic::Agent.config.register_callback(DEFAULT_CAPACITY_KEY) do |max_samples|
          NewRelic::Agent.logger.debug "CustomEventAggregator max_samples set to #{max_samples}"
          @lock.synchronize do
            @buffer.capacity = max_samples
          end
        end
      end

      def record(type, attributes)
        type = @type_strings[type]
        unless type =~ EVENT_TYPE_REGEX
          note_dropped_event(type)
          return false
        end

        event = [
          { TYPE => type, TIMESTAMP => Time.now.to_i },
          event_params(attributes, EVENT_PARAMS_CTX)
        ]

        stored = @lock.synchronize do
          @buffer.append(event)
        end
        stored
      end

      def harvest!
        results = []
        drop_count = 0
        @lock.synchronize do
          results.concat(@buffer.to_a)
          drop_count += @buffer.num_dropped
          @buffer.reset!
        end
        note_dropped_events(results.size, drop_count)
        results
      end

      def note_dropped_events(captured_count, dropped_count)
        total_count = captured_count + dropped_count
        if dropped_count > 0
          NewRelic::Agent.logger.warn("Dropped #{dropped_count} custom events out of #{total_count}.")
        end
        engine = NewRelic::Agent.instance.stats_engine
        engine.tl_record_supportability_metric_count("Events/Customer/Seen"   ,    total_count)
        engine.tl_record_supportability_metric_count("Events/Customer/Sent"   , captured_count)
        engine.tl_record_supportability_metric_count("Events/Customer/Dropped",  dropped_count)
      end

      def merge!(events)
        @lock.synchronize do
          events.each do |event|
            @buffer.append(event)
          end
        end
      end

      def reset!
        @lock.synchronize { @buffer.reset! }
      end

      def note_dropped_event(type)
        ::NewRelic::Agent.logger.log_once(:warn, "dropping_event_of_type:#{type}",
          "Invalid event type name '#{type}', not recording.")
        @buffer.note_dropped
      end

    end
  end
end
