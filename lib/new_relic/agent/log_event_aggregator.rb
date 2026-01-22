# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'new_relic/agent/event_aggregator'
require 'new_relic/agent/log_priority'
require 'new_relic/agent/log_event_attributes'

module NewRelic
  module Agent
    class LogEventAggregator < EventAggregator
      # Per-message keys
      LEVEL_KEY = 'level'.freeze
      MESSAGE_KEY = 'message'.freeze
      TIMESTAMP_KEY = 'timestamp'.freeze
      PRIORITY_KEY = 'priority'.freeze

      # Metric keys
      LINES = 'Logging/lines'.freeze
      DROPPED_METRIC = 'Logging/Forwarding/Dropped'.freeze
      SEEN_METRIC = 'Supportability/Logging/Forwarding/Seen'.freeze
      SENT_METRIC = 'Supportability/Logging/Forwarding/Sent'.freeze
      LOGGER_SUPPORTABILITY_FORMAT = 'Supportability/Logging/Ruby/Logger/%s'.freeze
      LOGSTASHER_SUPPORTABILITY_FORMAT = 'Supportability/Logging/Ruby/LogStasher/%s'.freeze
      LOGGING_SUPPORTABILITY_FORMAT = 'Supportability/Logging/Ruby/Logging/%s'.freeze
      METRICS_SUPPORTABILITY_FORMAT = 'Supportability/Logging/Metrics/Ruby/%s'.freeze
      FORWARDING_SUPPORTABILITY_FORMAT = 'Supportability/Logging/Forwarding/Ruby/%s'.freeze
      DECORATING_SUPPORTABILITY_FORMAT = 'Supportability/Logging/LocalDecorating/Ruby/%s'.freeze
      LABELS_SUPPORTABILITY_FORMAT = 'Supportability/Logging/Labels/Ruby/%s'.freeze
      MAX_BYTES = 32768 # 32 * 1024 bytes (32 kibibytes)

      named :LogEventAggregator
      buffer_class PrioritySampledBuffer

      capacity_key :'application_logging.forwarding.max_samples_stored'
      enabled_key :'application_logging.enabled'

      # Config keys
      OVERALL_ENABLED_KEY = :'application_logging.enabled'
      METRICS_ENABLED_KEY = :'application_logging.metrics.enabled'
      FORWARDING_ENABLED_KEY = :'application_logging.forwarding.enabled'
      DECORATING_ENABLED_KEY = :'application_logging.local_decorating.enabled'
      LABELS_ENABLED_KEY = :'application_logging.forwarding.labels.enabled'
      LOG_LEVEL_KEY = :'application_logging.forwarding.log_level'
      CUSTOM_ATTRIBUTES_KEY = :'application_logging.forwarding.custom_attributes'

      LOGGING_LEVELS = {
        0 => 'DEBUG',
        1 => 'INFO',
        2 => 'WARN',
        3 => 'ERROR',
        4 => 'FATAL'
      }.freeze

      attr_reader :attributes

      def initialize(events)
        super(events)
        @counter_lock = Mutex.new
        @seen = 0
        @seen_by_severity = Hash.new(0)
        @high_security = NewRelic::Agent.config[:high_security]
        @instrumentation_logger_enabled = NewRelic::Agent::Instrumentation::Logger.enabled?
        @attributes = NewRelic::Agent::LogEventAttributes.new

        register_for_done_configuring(events)
      end

      def capacity
        @buffer.capacity
      end

      def record(formatted_message, severity)
        return unless logger_enabled?

        severity = 'UNKNOWN' if severity.nil? || severity.empty?
        increment_event_counters(severity)

        return if formatted_message.nil? || formatted_message.empty?
        return unless monitoring_conditions_met?(severity)

        txn = NewRelic::Agent::Transaction.tl_current
        priority = LogPriority.priority_for(txn)

        return txn.add_log_event(create_event(priority, formatted_message, severity)) if txn

        @lock.synchronize do
          @buffer.append(priority: priority) do
            create_event(priority, formatted_message, severity)
          end
        end
      rescue
        nil
      end

      def record_logstasher_event(log)
        return unless logstasher_enabled?

        # LogStasher logs do not inherently include a message key, so most logs are recorded.
        # But when the key exists, we should not record the log if the message value is nil or empty.
        return if log.key?('message') && (log['message'].nil? || log['message'].empty?)

        severity = determine_severity(log)
        increment_event_counters(severity)

        return unless monitoring_conditions_met?(severity)

        txn = NewRelic::Agent::Transaction.tl_current
        priority = LogPriority.priority_for(txn)

        return txn.add_log_event(create_logstasher_event(priority, severity, log)) if txn

        @lock.synchronize do
          @buffer.append(priority: priority) do
            create_logstasher_event(priority, severity, log)
          end
        end
      rescue
        nil
      end

      def record_logging_event(log)
        return unless logging_enabled?

        severity = LOGGING_LEVELS[log.level]
        increment_event_counters(severity)

        return unless monitoring_conditions_met?(severity)

        txn = NewRelic::Agent::Transaction.tl_current
        priority = LogPriority.priority_for(txn)

        return txn.add_log_event(create_logging_event(priority, severity, log)) if txn

        @lock.synchronize do
          @buffer.append(priority: priority) do
            create_logging_event(priority, severity, log)
          end
        end
      rescue
        nil
      end

      def monitoring_conditions_met?(severity)
        !severity_too_low?(severity) && NewRelic::Agent.config[FORWARDING_ENABLED_KEY] && !@high_security
      end

      def determine_severity(log)
        log['level'] ? log['level'].to_s.upcase : 'UNKNOWN'
      end

      def increment_event_counters(severity)
        return unless NewRelic::Agent.config[METRICS_ENABLED_KEY]

        @counter_lock.synchronize do
          @seen += 1
          @seen_by_severity[severity] += 1
        end
      end

      def record_batch(txn, logs)
        # Ensure we have the same shared priority
        priority = LogPriority.priority_for(txn)
        logs.each do |log|
          log.first[PRIORITY_KEY] = priority
        end

        @lock.synchronize do
          logs.each do |log|
            @buffer.append(event: log)
          end
        end
      end

      def add_event_metadata(formatted_message, severity)
        metadata = {
          LEVEL_KEY => severity,
          TIMESTAMP_KEY => Process.clock_gettime(Process::CLOCK_REALTIME) * 1000
        }
        metadata[MESSAGE_KEY] = formatted_message unless formatted_message.nil?

        LinkingMetadata.append_trace_linking_metadata(metadata)
      end

      def create_prioritized_event(priority, event)
        [
          {
            PrioritySampledBuffer::PRIORITY_KEY => priority
          },
          event
        ]
      end

      def create_event(priority, formatted_message, severity)
        formatted_message = truncate_message(formatted_message)
        event = add_event_metadata(formatted_message, severity)

        create_prioritized_event(priority, event)
      end

      def create_logstasher_event(priority, severity, log)
        formatted_message = log['message'] ? truncate_message(log['message']) : nil
        event = add_event_metadata(formatted_message, severity)
        add_logstasher_event_attributes(event, log)

        create_prioritized_event(priority, event)
      end

      def add_logstasher_event_attributes(event, log)
        log_copy = log.dup
        # Delete previously reported attributes
        log_copy.delete('message')
        log_copy.delete('level')
        log_copy.delete('@timestamp')

        event['attributes'] = log_copy
      end

      def create_logging_event(priority, severity, log)
        formatted_message = truncate_message(log.data)
        event = add_event_metadata(formatted_message, severity)
        add_logging_event_attributes(event, log)

        create_prioritized_event(priority, event)
      end

      def add_logging_event_attributes(event, log)
        # binding.irb
        log_copy = log.dup
        # Delete previously reported attributes
        log_copy.delete('message')
        log_copy.delete('level')
        log_copy.delete('@timestamp')

        event['attributes'] = log_copy
      end

      def add_custom_attributes(custom_attributes)
        attributes.add_custom_attributes(custom_attributes)
      end

      def labels
        @labels ||= create_labels
      end

      # Because our transmission format (MELT) is different than historical
      # agent payloads, extract the munging here to keep the service focused
      # on the general harvest + transmit instead of the format.
      #
      # Payload shape matches the publicly documented MELT format.
      # https://docs.newrelic.com/docs/logs/log-api/introduction-log-api
      #
      # We have to keep the aggregated payloads in a separate shape, though, to
      # work with the priority sampling buffers
      def self.payload_to_melt_format(data)
        common_attributes = LinkingMetadata.append_service_linking_metadata({})

        # To save on unnecessary data transmission, trim the entity.type
        # sent by classic logs-in-context
        common_attributes.delete(ENTITY_TYPE_KEY)
        aggregator = NewRelic::Agent.agent.log_event_aggregator
        common_attributes.merge!(aggregator.attributes.custom_attributes)
        common_attributes.merge!(aggregator.labels)

        _, items = data
        payload = [{
          common: {attributes: common_attributes},
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

      def logger_enabled?
        @enabled && @instrumentation_logger_enabled
      end

      def logstasher_enabled?
        @enabled && NewRelic::Agent::Instrumentation::LogStasher.enabled?
      end

      def logging_enabled?
        @enabled && NewRelic::Agent::Instrumentation::Logging::Logger.enabled?
      end

      private

      # We record once-per-connect metrics for enabled/disabled state at the
      # point we consider the configuration stable (i.e. once we've gotten SSC)
      def register_for_done_configuring(events)
        events.subscribe(:server_source_configuration_added) do
          @high_security = NewRelic::Agent.config[:high_security]
          record_configuration_metric(LOGGER_SUPPORTABILITY_FORMAT, OVERALL_ENABLED_KEY)
          record_configuration_metric(LOGSTASHER_SUPPORTABILITY_FORMAT, OVERALL_ENABLED_KEY)
          record_configuration_metric(METRICS_SUPPORTABILITY_FORMAT, METRICS_ENABLED_KEY)
          record_configuration_metric(FORWARDING_SUPPORTABILITY_FORMAT, FORWARDING_ENABLED_KEY)
          record_configuration_metric(DECORATING_SUPPORTABILITY_FORMAT, DECORATING_ENABLED_KEY)
          record_configuration_metric(LABELS_SUPPORTABILITY_FORMAT, LABELS_ENABLED_KEY)

          add_custom_attributes(NewRelic::Agent.config[CUSTOM_ATTRIBUTES_KEY])
        end
      end

      def record_configuration_metric(format, key)
        state = NewRelic::Agent.config[key]
        label = if !enabled?
          'disabled'
        else
          state ? 'enabled' : 'disabled'
        end
        NewRelic::Agent.increment_metric(format % label)
      end

      def after_harvest(metadata)
        dropped_count = metadata[:seen] - metadata[:captured]
        note_dropped_events(metadata[:seen], dropped_count)
        record_supportability_metrics(metadata[:seen], metadata[:captured], dropped_count)
      end

      # To avoid paying the cost of metric recording on every line, we hold
      # these until harvest before recording them
      def record_customer_metrics
        return unless enabled?
        return unless NewRelic::Agent.config[METRICS_ENABLED_KEY]

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

      def note_dropped_events(total_count, dropped_count)
        if dropped_count > 0
          NewRelic::Agent.logger.warn("Dropped #{dropped_count} log events out of #{total_count}.")
        end
      end

      def record_supportability_metrics(total_count, captured_count, dropped_count)
        return unless total_count > 0

        NewRelic::Agent.increment_metric(DROPPED_METRIC, dropped_count)
        NewRelic::Agent.increment_metric(SEEN_METRIC, total_count)
        NewRelic::Agent.increment_metric(SENT_METRIC, captured_count)
      end

      def truncate_message(message)
        return message if message.bytesize <= MAX_BYTES

        message.byteslice(0...MAX_BYTES)
      end

      def configured_log_level_constant
        format_log_level_constant(NewRelic::Agent.config[LOG_LEVEL_KEY])
      end

      def format_log_level_constant(log_level)
        log_level.upcase.to_sym
      end

      def severity_too_low?(severity)
        severity_constant = format_log_level_constant(severity)
        # always record custom log levels
        return false unless Logger::Severity.constants.include?(severity_constant)

        Logger::Severity.const_get(severity_constant) < Logger::Severity.const_get(configured_log_level_constant)
      end

      def create_labels
        return NewRelic::EMPTY_HASH unless NewRelic::Agent.config[LABELS_ENABLED_KEY]

        downcased_exclusions = NewRelic::Agent.config[:'application_logging.forwarding.labels.exclude'].map(&:downcase)
        log_labels = {}

        NewRelic::Agent.config.parsed_labels.each do |parsed_label|
          next if downcased_exclusions.include?(parsed_label['label_type'].downcase)

          # labels are referred to as tags in the UI, so prefix the
          # label-related attributes with 'tags.*'
          log_labels["tags.#{parsed_label['label_type']}"] = parsed_label['label_value']
        end

        log_labels
      end
    end
  end
end
