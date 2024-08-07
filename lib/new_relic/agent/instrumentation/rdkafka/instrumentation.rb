# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'new_relic/agent/messaging'

module NewRelic::Agent::Instrumentation
  module Rdkafka
    MESSAGING_LIBRARY = 'Kafka'

    # TODO: serialization 
    def produce_with_new_relic(*args)
      topic_name = args[0][:topic]
      segment = NewRelic::Agent::Tracer.start_message_broker_segment(
        action: :produce,
        library: MESSAGING_LIBRARY,
        destination_type: :topic,
        destination_name: topic_name
      )

      headers = args[0][:headers] || {}
      ::NewRelic::Agent::DistributedTracing.insert_distributed_trace_headers(headers)
      yield(headers) # wrap in error catching
    ensure
      segment&.finish
    end

    # Adds two new metrics that are used to synthesize the entity relationship between AWS MSK and the APM entity:
    # MessageBroker/Kafka/Nodes/<host>:<port>
    # MessageBroker/Kafka/Nodes/<host>:<port>/<mode>/<topic>
    # where <host>:<port> is the Kafka server port, <mode> is either Produce or Consume and <topic> is the Kafka topic name
    # Updates Kafka container tests to validate the new metrics are present

    #                  Message/Kafka/Topic/Consume/Named/{topic_name}
    # OtherTransaction/Message/Kafka/Topic/Consume/Named/ruby-test-topic
    def each_with_new_relic(message)
      puts '***NR*** each_with_new_relic'
      headers = message&.headers || {}
      topic_name = message&.topic
      NewRelic::Agent::Messaging.wrap_message_broker_consume_transaction(
        library: MESSAGING_LIBRARY,
        destination_type: :topic,
        destination_name: topic_name,
        headers: headers,
        action: :consume
      ) do
        yield
      end
    end

    def create_kafka_metrics(action:, topic:)
      # NewRelic::Agent.record_metric("MessageBroker/Kafka/Nodes/#{host}:#{port}/#{action}/#{topic}", 1)
      # NewRelic::Agent.record_metric("MessageBroker/Kafka/Nodes/#{host}:#{port}", 1)
    end
  end
end
