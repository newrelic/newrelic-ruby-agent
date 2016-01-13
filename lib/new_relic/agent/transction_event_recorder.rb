# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require 'new_relic/agent/transaction_event_aggregator'
require 'new_relic/agent/synthetics_event_aggregator'

module NewRelic
  module Agent
    # This is responsibile for recording transaction events and managing
    # the relationship between events generated from synthetics requests
    # vs normal requests.
    class TransactionEventRecorder
      attr_reader :transaction_event_aggregator
      attr_reader :synthetics_event_aggregator

      def initialize
        @transaction_event_aggregator = NewRelic::Agent::TransactionEventAggregator.new
        @synthetics_event_aggregator = NewRelic::Agent::SyntheticsEventAggregator.new
      end

      def record payload
        return unless NewRelic::Agent.config[:'analytics_events.enabled']

        event = TransactionEvent.new payload

        if event.synthetics?
          _, rejected = synthetics_event_aggregator.append_or_reject event.to_collector_array
          transaction_event_aggregator.record event if rejected
        else
          transaction_event_aggregator.record event.to_collector_array
        end
      end
    end
  end
end
