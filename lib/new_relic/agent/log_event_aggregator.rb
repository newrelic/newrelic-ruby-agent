# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require 'new_relic/agent/event_aggregator'
require 'new_relic/agent/log_priority'

module NewRelic
  module Agent
    class LogEventAggregator < EventAggregator

      # Per-message keys
      LEVEL_KEY = "level".freeze
      MESSAGE_KEY = "message".freeze
      TIMESTAMP_KEY = "timestamp".freeze

      # Metric keys
      LINES = "Logging/lines".freeze

      named :LogEventAggregator
      # TODO use the right value when the collector starts reporting it
      capacity_key :'custom_insights_events.max_samples_stored'
      #capacity_key :'log_sending.max_samples_stored'
      enabled_key :'application_logging.forwarding.enabled'
      buffer_class PrioritySampledBuffer

      def initialize(events)
        super(events)
        @counter_lock = Mutex.new
        @seen = 0
        @seen_by_severity = Hash.new(0)
      end

      def capacity
        @buffer.capacity
      end

      def record(formatted_message, severity)
        @counter_lock.synchronize do
          @seen += 1
          @seen_by_severity[severity] += 1
        end

        return unless enabled?

        priority = LogPriority.priority_for(severity)

        txn = NewRelic::Agent::Transaction.tl_current
        if txn
          return txn.add_log_event(create_event(priority, formatted_message, severity))
        else
          return @lock.synchronize do
            @buffer.append(priority: priority) do
              create_event(priority, formatted_message, severity)
            end
          end
        end
      rescue
        nil
      end

      def record_batch txn, logs
        # Capture our finalized priority
        logs.each do |log|
          log.first["priority"] = LogPriority.priority_for(log.last["level"], txn)
        end

        @lock.synchronize do
          logs.each do |log|
            @buffer.append(event: log)
          end
        end
      end

      def create_event priority, formatted_message, severity
        event = LinkingMetadata.append_trace_linking_metadata({
          LEVEL_KEY => severity,
          MESSAGE_KEY => formatted_message,
          TIMESTAMP_KEY => Process.clock_gettime(Process::CLOCK_REALTIME)
        })

        [
          {
            PrioritySampledBuffer::PRIORITY_KEY => priority
          },
          event
        ]
      end

      # Because our transmission format (MELT) is different than historical
      # agent payloads, extract the munging here to keep the service focused
      # on the general harvest + transmit instead of the format.
      #
      # We have to keep the aggregated payloads in a separate shape, though, to
      # work with the priority sampling buffers
      def self.payload_to_melt_format(data)
        common_attributes = LinkingMetadata.append_service_linking_metadata({})

        _, items = data
        payload = [{
          common: { attributes: common_attributes },
          logs: items.map(&:last)
        }]

        return [payload, items.size]
      end

      def harvest!
        record_customer_metrics()
        super
      end

      def reset!
        @counter_lock.synchronize do
          @seen = 0
          @seen_by_severity.clear
        end
        super
      end

      private

      def register_capacity_callback
        NewRelic::Agent.config.register_callback(self.class.capacity_key) do |max_samples|
          NewRelic::Agent.logger.debug "#{self.class.named} max_samples set to #{max_samples}"
          @lock.synchronize do
            @buffer.capacity = max_samples
          end
        end
      end

      def after_harvest metadata
        dropped_count = metadata[:seen] - metadata[:captured]
        note_dropped_events(metadata[:seen], dropped_count)
        record_supportability_metrics(metadata[:seen], metadata[:captured], dropped_count)
      end

      # To avoid paying the cost of metric recording on every line, we hold
      # these until harvest before recording them
      def record_customer_metrics
        @counter_lock.synchronize do
          return unless @seen > 0

          NewRelic::Agent.increment_metric(LINES, @seen)
          @seen_by_severity.each do |(severity, count)|
            NewRelic::Agent.increment_metric(line_metric_name_by_severity(severity), count)
          end

          @seen = 0
          @seen_by_severity.clear
        end
      end

      def line_metric_name_by_severity(severity)
        @line_metrics ||= {}
        @line_metrics[severity] ||= "Logging/lines/#{severity}".freeze
      end

      def note_dropped_events total_count, dropped_count
        if dropped_count > 0
          NewRelic::Agent.logger.warn("Dropped #{dropped_count} log events out of #{total_count}.")
        end
      end

      def record_supportability_metrics total_count, captured_count, dropped_count
        return unless total_count > 0

        NewRelic::Agent.increment_metric("Supportability/Logging/Customer/Seen", total_count)
        NewRelic::Agent.increment_metric("Supportability/Logging/Customer/Sent", captured_count)
        NewRelic::Agent.increment_metric("Supportability/Logging/Customer/Dropped", dropped_count)
      end
    end
  end
end
