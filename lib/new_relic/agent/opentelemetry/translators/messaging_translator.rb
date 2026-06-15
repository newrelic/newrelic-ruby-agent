# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'base_translator'

module NewRelic
  module Agent
    module OpenTelemetry
      class MessagingTranslator < BaseTranslator
        # OTel seems to be inconsitent with dot or underscore,
        # so we handle both just in case.
        DESTINATION_TYPES_MAP = {
          consumer: {
            'kafka' => :topic,
            'rabbitmq' => :queue,
            'aws.sqs' => :queue,
            'aws_sqs' => :queue,
            'aws.sns' => :topic,
            'aws_sns' => :topic,
            'aws.kinesis' => :stream,
            'aws_kinesis' => :stream
          }.freeze,
          producer: {
            'kafka' => :topic,
            'rabbitmq' => :exchange,
            'aws.sqs' => :queue,
            'aws_sqs' => :queue,
            'aws.sns' => :topic,
            'aws_sns' => :topic,
            'aws.kinesis' => :stream,
            'aws_kinesis' => :stream
          }.freeze
        }.freeze

        # `messaging.destination_kind` is a v1.17 attribute that we
        # should honor it when present.
        DESTINATION_KIND_MAP = {
          'queue' => :queue,
          'topic' => :topic
        }.freeze

        TEMP_MAP = {
          queue: :temporary_queue,
          topic: :temporary_topic
        }.freeze

        ACTION_MAP = {
          consumer: :consume,
          producer: :produce
        }.freeze

        # Capitalize the OTel `messaging.system` value to match the casing used
        # by NR messaging instrumentation.
        LIBRARY_MAP = {
          'kafka' => 'Kafka',
          'rabbitmq' => 'RabbitMQ',
          'aws.sqs' => 'SQS',
          'aws_sqs' => 'SQS',
          'aws.sns' => 'SNS',
          'aws_sns' => 'SNS',
          'aws.kinesis' => 'Kinesis',
          'aws_kinesis' => 'Kinesis'
        }.freeze

        ROUTING_KEY_OTEL_KEYS = AttributeMappings::MESSAGING_PRODUCER_MAPPINGS
          .dig('routingKey', :otel_keys)
        CORRELATION_ID_OTEL_KEY = AttributeMappings::MESSAGING_PRODUCER_MAPPINGS
          .dig('correlation_id', :otel_keys).first

        class << self
          def mappings_hash(kind)
            kind == :consumer ? AttributeMappings::MESSAGING_CONSUMER_MAPPINGS : AttributeMappings::MESSAGING_PRODUCER_MAPPINGS
          end

          def add_specialized_attributes(result: {}, name: nil, attributes: nil, instrumentation_scope: nil, kind: nil)
            result[:for_segment_api][:action] = ACTION_MAP[kind]
            result[:for_segment_api][:destination_type] = determine_destination_type(attributes, kind)
            if (system = attributes['messaging.system'])
              result[:for_segment_api][:library] = LIBRARY_MAP[system] || system
            end

            add_producer_segment_params(result, attributes) if kind == :producer

            result
          end

          def add_producer_segment_params(result, attributes)
            params = {
              routing_key: ROUTING_KEY_OTEL_KEYS.map { |k| attributes[k] }.compact.first,
              correlation_id: attributes[CORRELATION_ID_OTEL_KEY]
            }.compact

            result[:for_segment_api][:parameters] = params unless params.empty?
          end

          def determine_destination_type(attributes, kind)
            type = explicit_destination_kind(attributes) ||
              DESTINATION_TYPES_MAP[kind][attributes['messaging.system']] ||
              :unknown
            return type unless attributes['messaging.destination.temporary'] == true

            TEMP_MAP[type] || type
          end

          private

          def explicit_destination_kind(attributes)
            value = attributes['messaging.destination_kind']
            DESTINATION_KIND_MAP[value] if value
          end
        end
      end
    end
  end
end
