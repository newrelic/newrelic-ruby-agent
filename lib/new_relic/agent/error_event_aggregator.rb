# -*- ruby -*-
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/event_aggregator'
require 'new_relic/agent/transaction_error_primitive'
require 'new_relic/agent/priority_sampled_buffer'

module NewRelic
  module Agent
    class ErrorEventAggregator < EventAggregator

      named :ErrorEventAggregator
      capacity_key :'error_collector.max_event_samples_stored'
      enabled_key :'error_collector.capture_events'
      buffer_class PrioritySampledBuffer

      def record noticed_error, transaction_payload = nil
        return unless enabled?

        priority = (transaction_payload && transaction_payload[:priority]) || rand.round(6)

        @lock.synchronize do
          @buffer.append(priority: priority) do
            create_event(noticed_error, transaction_payload)
          end
          notify_if_full
        end
      end

      private

      def create_event noticed_error, transaction_payload
        TransactionErrorPrimitive.create noticed_error, transaction_payload
      end
    end
  end
end
