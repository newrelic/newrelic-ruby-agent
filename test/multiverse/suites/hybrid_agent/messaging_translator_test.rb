# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      class MessagingTranslatorTest < Minitest::Test
        def translator
          MessagingTranslator
        end

        def assert_destination_type(expected, attrs, kind)
          assert_equal expected, translator.determine_destination_type(attrs, kind)
        end

        def test_mappings_hash_returns_consumer_mappings_for_consumer_kind
          assert_same AttributeMappings::MESSAGING_CONSUMER_MAPPINGS, translator.mappings_hash(:consumer)
        end

        def test_mappings_hash_returns_producer_mappings_for_producer_kind
          assert_same AttributeMappings::MESSAGING_PRODUCER_MAPPINGS, translator.mappings_hash(:producer)
        end

        def test_determine_destination_type_kafka_is_topic_for_consumer
          assert_destination_type :topic, {'messaging.system' => 'kafka'}, :consumer
        end

        def test_determine_destination_type_kafka_is_topic_for_producer
          assert_destination_type :topic, {'messaging.system' => 'kafka'}, :producer
        end

        def test_determine_destination_type_rabbitmq_is_queue_for_consumer
          assert_destination_type :queue, {'messaging.system' => 'rabbitmq'}, :consumer
        end

        def test_determine_destination_type_rabbitmq_is_exchange_for_producer
          assert_destination_type :exchange, {'messaging.system' => 'rabbitmq'}, :producer
        end

        def test_determine_destination_type_unknown_system_returns_unknown
          attrs = {'messaging.system' => 'made_up_broker'}

          assert_destination_type :unknown, attrs, :consumer
          assert_destination_type :unknown, attrs, :producer
        end

        def test_determine_destination_type_temporary_queue_maps_to_temporary_queue
          attrs = {'messaging.system' => 'aws_sqs', 'messaging.destination.temporary' => true}

          assert_destination_type :temporary_queue, attrs, :consumer
        end

        def test_determine_destination_type_temporary_topic_maps_to_temporary_topic
          attrs = {'messaging.system' => 'kafka', 'messaging.destination.temporary' => true}

          assert_destination_type :temporary_topic, attrs, :producer
        end

        def test_determine_destination_type_temporary_false_does_not_remap
          attrs = {'messaging.system' => 'kafka', 'messaging.destination.temporary' => false}

          assert_destination_type :topic, attrs, :consumer
        end

        def test_determine_destination_type_temporary_unknown_stays_unknown
          attrs = {'messaging.system' => 'mystery_broker', 'messaging.destination.temporary' => true}

          assert_destination_type :unknown, attrs, :consumer
        end

        def test_determine_destination_type_honors_explicit_destination_kind_v117
          attrs = {'messaging.system' => 'rabbitmq', 'messaging.destination_kind' => 'topic'}

          assert_destination_type :topic, attrs, :producer
        end

        def test_determine_destination_type_explicit_kind_overrides_system_inference
          # rabbitmq producer would infer :exchange, but explicit kind wins
          attrs = {'messaging.system' => 'rabbitmq', 'messaging.destination_kind' => 'queue'}

          assert_destination_type :queue, attrs, :producer
        end

        def test_determine_destination_type_aws_sqs_with_dot
          assert_destination_type :queue, {'messaging.system' => 'aws.sqs'}, :producer
        end

        def test_determine_destination_type_aws_sns_with_dot
          assert_destination_type :topic, {'messaging.system' => 'aws.sns'}, :producer
        end

        def test_determine_destination_type_aws_sns_underscore
          assert_destination_type :topic, {'messaging.system' => 'aws_sns'}, :producer
        end

        def test_determine_destination_type_aws_kinesis_underscore_for_consumer
          assert_destination_type :stream, {'messaging.system' => 'aws_kinesis'}, :consumer
        end

        def test_determine_destination_type_aws_kinesis_underscore_for_producer
          assert_destination_type :stream, {'messaging.system' => 'aws_kinesis'}, :producer
        end

        def test_determine_destination_type_aws_kinesis_with_dot
          assert_destination_type :stream, {'messaging.system' => 'aws.kinesis'}, :producer
        end

        def test_translate_consumer_sets_action_to_consume
          result = translator.translate(attributes: {'messaging.system' => 'kafka'}, kind: :consumer)

          assert_equal :consume, result[:for_segment_api][:action]
        end

        def test_translate_consumer_sets_destination_type_in_segment_api
          result = translator.translate(attributes: {'messaging.system' => 'rabbitmq'}, kind: :consumer)

          assert_equal :queue, result[:for_segment_api][:destination_type]
        end

        def test_translate_consumer_routes_destination_name_via_mappings
          attrs = {'messaging.destination.name' => 'orders.queue', 'messaging.system' => 'rabbitmq'}
          result = translator.translate(attributes: attrs, kind: :consumer)

          assert_equal 'orders.queue', result[:for_segment_api][:destination_name]
        end

        def test_translate_consumer_routes_library_to_segment_api
          result = translator.translate(attributes: {'messaging.system' => 'kafka'}, kind: :consumer)

          assert_equal 'Kafka', result[:for_segment_api][:library]
        end

        def test_translate_consumer_puts_unrecognized_attrs_in_custom
          attrs = {'messaging.system' => 'kafka', 'messaging.kafka.partition' => 3}
          result = translator.translate(attributes: attrs, kind: :consumer)

          assert_equal 3, result[:custom]['messaging.kafka.partition']
        end

        def test_translate_consumer_routes_messaging_operation_type_to_custom
          attrs = {'messaging.system' => 'kafka', 'messaging.operation.type' => 'process'}
          result = translator.translate(attributes: attrs, kind: :consumer)

          assert_equal 'process', result[:custom]['messaging.operation.type']
        end

        def test_translate_producer_sets_action_to_produce
          result = translator.translate(attributes: {'messaging.system' => 'kafka'}, kind: :producer)

          assert_equal :produce, result[:for_segment_api][:action]
        end

        def test_translate_producer_sets_destination_type_in_segment_api
          result = translator.translate(attributes: {'messaging.system' => 'rabbitmq'}, kind: :producer)

          assert_equal :exchange, result[:for_segment_api][:destination_type]
        end

        def test_translate_producer_routes_destination_name_via_mappings
          attrs = {'messaging.destination.name' => 'events.topic', 'messaging.system' => 'kafka'}
          result = translator.translate(attributes: attrs, kind: :producer)

          assert_equal 'events.topic', result[:for_segment_api][:destination_name]
        end

        def test_translate_producer_routes_library_to_segment_api
          result = translator.translate(attributes: {'messaging.system' => 'kafka'}, kind: :producer)

          assert_equal 'Kafka', result[:for_segment_api][:library]
        end

        def test_translate_producer_puts_unrecognized_attrs_in_custom
          attrs = {'messaging.system' => 'kafka', 'messaging.kafka.partition' => 7}
          result = translator.translate(attributes: attrs, kind: :producer)

          assert_equal 7, result[:custom]['messaging.kafka.partition']
        end

        def test_translate_producer_routes_messaging_operation_type_to_custom
          attrs = {'messaging.system' => 'kafka', 'messaging.operation.type' => 'publish'}
          result = translator.translate(attributes: attrs, kind: :producer)

          assert_equal 'publish', result[:custom]['messaging.operation.type']
        end

        def test_translate_falls_back_to_legacy_destination_key
          attrs = {'messaging.destination' => 'legacy.topic', 'messaging.system' => 'kafka'}
          result = translator.translate(attributes: attrs, kind: :producer)

          assert_equal 'legacy.topic', result[:for_segment_api][:destination_name]
        end

        def test_translate_returns_translator_class
          result = translator.translate(attributes: {'messaging.system' => 'kafka'}, kind: :consumer)

          assert_same MessagingTranslator, result[:translator]
        end
      end
    end
  end
end
