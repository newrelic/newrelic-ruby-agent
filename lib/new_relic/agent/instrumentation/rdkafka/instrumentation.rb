# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'new_relic/agent/messaging'

module NewRelic::Agent::Instrumentation
  module Rdkafka
    MESSAGING_LIBRARY = 'Kafka'
    PRODUCE = 'Produce'
    CONSUME = 'Consume'

    INSTRUMENTATION_NAME = 'Rdkafka'

    def produce_with_new_relic(*args)
      NewRelic::Agent.record_instrumentation_invocation(INSTRUMENTATION_NAME)

      topic_name = args[0][:topic]
      segment = NewRelic::Agent::Tracer.start_message_broker_segment(
        action: :produce,
        library: MESSAGING_LIBRARY,
        destination_type: :topic,
        destination_name: topic_name
      )
      create_kafka_metrics(action: PRODUCE, topic: topic_name)

      headers = args[0][:headers] || {}
      ::NewRelic::Agent::DistributedTracing.insert_distributed_trace_headers(headers)

      NewRelic::Agent::Tracer.capture_segment_error(segment) { yield(headers) }
    ensure
      segment&.finish
    end

    def each_with_new_relic(message)
      NewRelic::Agent.record_instrumentation_invocation(INSTRUMENTATION_NAME)

      headers = message&.headers || {}
      topic_name = message&.topic

      NewRelic::Agent::Messaging.wrap_message_broker_consume_transaction(
        library: MESSAGING_LIBRARY,
        destination_type: :topic,
        destination_name: topic_name,
        headers: headers,
        action: :consume
      ) do
        create_kafka_metrics(action: CONSUME, topic: topic_name)
        yield
      end
    end

    def create_kafka_metrics(action:, topic:)
      hosts = []
      # both 'bootstrap.servers' and 'metadata.broker.list' are valid ways to specify the Kafka server
      hosts << @nr_config[:'bootstrap.servers'] if @nr_config[:'bootstrap.servers']
      hosts << @nr_config[:'metadata.broker.list'] if @nr_config[:'metadata.broker.list']
      hosts.each do |host|
        NewRelic::Agent.record_metric("MessageBroker/Kafka/Nodes/#{host}/#{action}/#{topic}", 1)
        NewRelic::Agent.record_metric("MessageBroker/Kafka/Nodes/#{host}", 1)
      end
    end
  end

  module RdkafkaConfig
    def set_nr_config(producer_or_consumer)
      producer_or_consumer.instance_variable_set(:@nr_config, self)
    end
  end
end
