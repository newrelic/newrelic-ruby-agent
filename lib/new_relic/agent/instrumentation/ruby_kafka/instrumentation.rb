# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module RubyKafka
    MESSAGING_LIBRARY = 'Kafka'
    PRODUCE = 'Produce'
    CONSUME = 'Consume'

    INSTRUMENTATION_NAME = 'ruby-kafka'

    def produce_with_new_relic(value, **kwargs)
      NewRelic::Agent.record_instrumentation_invocation(INSTRUMENTATION_NAME)

      topic_name = kwargs[:topic]
      segment = NewRelic::Agent::Tracer.start_message_broker_segment(
        action: :produce,
        library: MESSAGING_LIBRARY,
        destination_type: :topic,
        destination_name: topic_name
      )
      create_kafka_metrics(action: PRODUCE, topic: topic_name)

      headers = kwargs[:headers] || {}
      ::NewRelic::Agent::DistributedTracing.insert_distributed_trace_headers(headers)

      NewRelic::Agent::Tracer.capture_segment_error(segment) { yield(headers) }
    ensure
      segment&.finish
    end

    def each_message_with_new_relic(message)
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
      @nr_config.each do |seed_broker|
        host = "#{seed_broker&.host}:#{seed_broker&.port}"
        NewRelic::Agent.record_metric("MessageBroker/Kafka/Nodes/#{host}/#{action}/#{topic}", 1)
        NewRelic::Agent.record_metric("MessageBroker/Kafka/Nodes/#{host}", 1)
      end
    end
  end

  module RubyKafkaConfig
    def set_nr_config(producer_or_consumer)
      producer_or_consumer.instance_variable_set(:@nr_config, @seed_brokers)
    end
  end
end
