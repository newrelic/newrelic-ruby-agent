# -*- ruby -*-
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/sampled_buffer'
require 'new_relic/agent/payload_metric_mapping'

module NewRelic
  module Agent
    class ErrorEventAggregator
      EVENT_TYPE = "TransactionError".freeze

      def initialize
        @lock = Mutex.new
        @error_event_buffer = SampledBuffer.new Agent.config[:'error_collector.max_event_samples_stored']
        register_config_callbacks
      end

      def enabled?
        Agent.config[:'error_collector.capture_events']
      end

      def append_event noticed_error, transaction_payload
        return unless enabled?

        @lock.synchronize do
          @error_event_buffer.append do
            event_for_collector(noticed_error, transaction_payload)
          end
        end
      end

      def harvest!
        @lock.synchronize do
          samples = @error_event_buffer.to_a
          # Eventually the logic for adding reservoir data will move to the sampled buffer
          # so it can be shared with the other event aggregators. We'll first get it working
          # here and then promote the functionality later.
          stats = reservoir_stats
          @error_event_buffer.reset!
          [stats, samples]
        end
      end

      def reset!
        @lock.synchronize do
          @error_event_buffer.reset!
        end
      end

      # samples will have already been transformed into
      # collector primitives by event_for_collector
      def merge! payload
        @lock.synchronize do
          _, samples = payload
          @error_event_buffer.decrement_lifetime_counts_by samples.count
          samples.each { |s| @error_event_buffer.append s }
        end
      end

      def has_metadata?
        true
      end

      private

      def reservoir_stats
        {
          :reservoir_size => Agent.config[:'error_collector.max_event_samples_stored'],
          :events_seen => @error_event_buffer.num_seen
        }
      end

      def register_config_callbacks
        NewRelic::Agent.config.register_callback(:'error_collector.max_event_samples_stored') do |max_samples|
          NewRelic::Agent.logger.debug "ErrorEventAggregator max_samples set to #{max_samples}"
          @lock.synchronize { @error_event_buffer.capacity = max_samples }
        end

        NewRelic::Agent.config.register_callback(:'error_collector.capture_events') do |enabled|
          ::NewRelic::Agent.logger.debug "Error events will #{enabled ? '' : 'not '}be sent to the New Relic service."
        end
      end

      def event_for_collector noticed_error, transaction_payload
        [
          intrinsic_attributes_for(noticed_error, transaction_payload),
          noticed_error.custom_attributes,
          noticed_error.agent_attributes
        ]
      end

      def intrinsic_attributes_for noticed_error, transaction_payload
        attrs = {
          :type => EVENT_TYPE,
          :'error.class' => noticed_error.exception_class_name,
          :'error.message' => noticed_error.message,
          :timestamp => noticed_error.timestamp.to_f,
          :transactionName => transaction_payload[:name],
          :duration => transaction_payload[:duration]
        }
        attrs[:port] = noticed_error.request_port if noticed_error.request_port

        append_synthetics transaction_payload, attrs
        append_cat transaction_payload, attrs
        PayloadMetricMapping.append_mapped_metrics transaction_payload[:metrics], attrs

        attrs
      end

      def append_synthetics transaction_payload, sample
        sample[:'nr.syntheticsResourceId'] = transaction_payload[:synthetics_resource_id] if transaction_payload[:synthetics_resource_id]
        sample[:'nr.syntheticsJobId'] = transaction_payload[:synthetics_job_id] if transaction_payload[:synthetics_job_id]
        sample[:'nr.syntheticsMonitorId'] = transaction_payload[:synthetics_monitor_id] if transaction_payload[:synthetics_monitor_id]
      end

      def append_cat transaction_payload, sample
        sample[:'nr.transactionGuid'] = transaction_payload[:guid] if transaction_payload[:guid]
        sample[:'nr.referringTransactionGuid'] = transaction_payload[:referring_transaction_guid] if transaction_payload[:referring_transaction_guid]
      end
    end
  end
end
