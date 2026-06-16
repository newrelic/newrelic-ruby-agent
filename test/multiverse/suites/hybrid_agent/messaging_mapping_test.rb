# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module Trace
        class MessagingMappingTest < Minitest::Test
          def setup
            @tracer = NewRelic::Agent::OpenTelemetry::Trace::Tracer.new('OTelMessagingClient')
            harvest_transaction_events!
            harvest_span_events!
            reset_adaptive_samplers!
          end

          def teardown
            mocha_teardown
            # Tests that exercise remote-parent paths call into the
            # AdaptiveSampler (which has a 10-call-per-period budget). Reset
            # to avoid bleeding state into later tests in the suite.
            reset_adaptive_samplers!
          end

          def reset_adaptive_samplers!
            agent = NewRelic::Agent.instance
            return unless agent

            target = NewRelic::Agent.config[:sampling_target]
            period = NewRelic::Agent.config[:sampling_target_period_in_seconds]

            agent.instance_variable_set(:@adaptive_sampler, NewRelic::Agent::AdaptiveSampler.new(target, period))
            agent.instance_variable_set(:@adaptive_sampler_remote_parent_sampled, NewRelic::Agent::AdaptiveSampler.new(target, period))
            agent.instance_variable_set(:@adaptive_sampler_remote_parent_not_sampled, NewRelic::Agent::AdaptiveSampler.new(target, period))
          end

          def consumer_v_1_30_attrs
            {
              'messaging.system' => 'kafka',
              'messaging.destination.name' => 'orders.topic',
              'messaging.kafka.message.key' => 'user-42',
              'server.address' => 'broker.example',
              'server.port' => '9092',
              'messaging.kafka.partition' => 3
            }
          end

          def consumer_v_1_24_attrs
            {
              'messaging.system' => 'rabbitmq',
              'messaging.destination.name' => 'orders.queue',
              'messaging.rabbitmq.destination.routing_key' => 'orders.created',
              'server.address' => 'broker.example',
              'server.port' => '5672',
              'messaging.rabbitmq.delivery_tag' => 99
            }
          end

          def consumer_v_1_17_attrs
            {
              'messaging.system' => 'rabbitmq',
              'messaging.destination' => 'orders.queue',
              'messaging.destination_kind' => 'queue',
              'messaging.rabbitmq.destination.routing_key' => 'orders.created',
              'net.peer.name' => 'broker.example',
              'net.peer.port' => '5672',
              'messaging.protocol' => 'AMQP'
            }
          end

          def producer_v_1_30_attrs
            {
              'messaging.system' => 'kafka',
              'messaging.destination.name' => 'events.topic',
              'messaging.kafka.message.key' => 'user-99',
              'messaging.message.conversation_id' => 'corr-abc',
              'server.address' => 'broker.example',
              'server.port' => '9092',
              'messaging.kafka.partition' => 7
            }
          end

          def producer_v_1_24_attrs
            {
              'messaging.system' => 'rabbitmq',
              'messaging.destination.name' => 'events.exchange',
              'messaging.rabbitmq.destination.routing_key' => 'events.created',
              'messaging.message.conversation_id' => 'corr-def',
              'server.address' => 'broker.example',
              'server.port' => '5672',
              'messaging.rabbitmq.delivery_tag' => 12
            }
          end

          def producer_v_1_17_attrs
            {
              'messaging.system' => 'rabbitmq',
              'messaging.destination' => 'events.exchange',
              'messaging.destination_kind' => 'queue',
              'messaging.rabbitmq.destination.routing_key' => 'events.created',
              'messaging.message.conversation_id' => 'corr-ghi',
              'net.peer.name' => 'broker.example',
              'net.peer.port' => '5672',
              'messaging.protocol' => 'AMQP'
            }
          end

          def run_consumer_span(attrs)
            in_transaction(category: :web) do |txn|
              txn.stubs(:sampled?).returns(true)

              @tracer.in_span('consume', attributes: attrs.dup, kind: :consumer) do |span|
                # noop
              end
            end
          end

          def run_producer_span(attrs)
            in_transaction(category: :web) do |txn|
              txn.stubs(:sampled?).returns(true)

              @tracer.in_span('publish', attributes: attrs.dup, kind: :producer) do |span|
                # noop
              end
            end
          end

          # ---------- consumer v1.30 ----------

          def test_consumer_v_1_30_segment_properties
            transaction = run_consumer_span(consumer_v_1_30_attrs)
            segment = transaction.segments[1]

            assert_instance_of NewRelic::Agent::Transaction::MessageBrokerSegment, segment
            assert_equal 'MessageBroker/Kafka/Topic/Consume/Named/orders.topic', segment.name
            assert_equal 'Kafka', segment.library
            assert_equal :topic, segment.destination_type
            assert_equal 'orders.topic', segment.destination_name
            assert_equal :consume, segment.action
          end

          def test_consumer_v_1_30_metrics
            run_consumer_span(consumer_v_1_30_attrs)

            assert_metrics_recorded([
              'MessageBroker/Kafka/Topic/Consume/Named/orders.topic'
            ])
          end

          def test_consumer_v_1_30_agent_attributes
            attrs = consumer_v_1_30_attrs
            transaction = run_consumer_span(attrs)
            segment = transaction.segments[1]
            agent = segment.attributes.agent_attributes_for(AttributeFilter::DST_TRANSACTION_TRACER)

            assert_equal attrs['messaging.system'], agent['messaging.system']
            assert_equal attrs['messaging.destination.name'], agent['message.queueName']
            assert_equal attrs['server.address'], agent['host']
            assert_equal attrs['server.port'], agent['port']
            assert_equal attrs['messaging.kafka.message.key'], agent['message.routingKey']
          end

          def test_consumer_v_1_30_custom_attributes
            run_consumer_span(consumer_v_1_30_attrs)

            spans = harvest_span_events!
            span = spans[1][0]
            custom = span[1]

            keys_assigned_elsewhere = %w[
              messaging.destination.name
              messaging.kafka.message.key
              server.address
              server.port
            ]

            assert_empty custom.keys & keys_assigned_elsewhere
            assert_equal 3, custom['messaging.kafka.partition']
          end

          # ---------- consumer v1.24 ----------

          def test_consumer_v_1_24_segment_properties
            transaction = run_consumer_span(consumer_v_1_24_attrs)
            segment = transaction.segments[1]

            assert_instance_of NewRelic::Agent::Transaction::MessageBrokerSegment, segment
            assert_equal 'MessageBroker/RabbitMQ/Queue/Consume/Named/orders.queue', segment.name
            assert_equal 'RabbitMQ', segment.library
            assert_equal :queue, segment.destination_type
            assert_equal 'orders.queue', segment.destination_name
            assert_equal :consume, segment.action
          end

          def test_consumer_v_1_24_metrics
            run_consumer_span(consumer_v_1_24_attrs)

            assert_metrics_recorded([
              'MessageBroker/RabbitMQ/Queue/Consume/Named/orders.queue'
            ])
          end

          def test_consumer_v_1_24_agent_attributes
            attrs = consumer_v_1_24_attrs
            transaction = run_consumer_span(attrs)
            segment = transaction.segments[1]
            agent = segment.attributes.agent_attributes_for(AttributeFilter::DST_TRANSACTION_TRACER)

            assert_equal attrs['messaging.system'], agent['messaging.system']
            assert_equal attrs['messaging.destination.name'], agent['message.queueName']
            assert_equal attrs['server.address'], agent['host']
            assert_equal attrs['server.port'], agent['port']
            assert_equal attrs['messaging.rabbitmq.destination.routing_key'], agent['message.routingKey']
          end

          def test_consumer_v_1_24_custom_attributes
            run_consumer_span(consumer_v_1_24_attrs)

            spans = harvest_span_events!
            span = spans[1][0]
            custom = span[1]

            keys_assigned_elsewhere = %w[
              messaging.destination.name
              messaging.rabbitmq.destination.routing_key
              server.address
              server.port
            ]

            assert_empty custom.keys & keys_assigned_elsewhere
            assert_equal 99, custom['messaging.rabbitmq.delivery_tag']
          end

          # ---------- consumer v1.17 ----------

          def test_consumer_v_1_17_segment_properties
            transaction = run_consumer_span(consumer_v_1_17_attrs)
            segment = transaction.segments[1]

            assert_instance_of NewRelic::Agent::Transaction::MessageBrokerSegment, segment
            # destination_kind is honored over system inference (rabbitmq consumer
            # would have inferred :queue anyway, but the explicit kind wins)
            assert_equal 'MessageBroker/RabbitMQ/Queue/Consume/Named/orders.queue', segment.name
            assert_equal 'RabbitMQ', segment.library
            assert_equal :queue, segment.destination_type
            assert_equal 'orders.queue', segment.destination_name
            assert_equal :consume, segment.action
          end

          def test_consumer_v_1_17_metrics
            run_consumer_span(consumer_v_1_17_attrs)

            assert_metrics_recorded([
              'MessageBroker/RabbitMQ/Queue/Consume/Named/orders.queue'
            ])
          end

          def test_consumer_v_1_17_agent_attributes
            attrs = consumer_v_1_17_attrs
            transaction = run_consumer_span(attrs)
            segment = transaction.segments[1]
            agent = segment.attributes.agent_attributes_for(AttributeFilter::DST_TRANSACTION_TRACER)

            assert_equal attrs['messaging.system'], agent['messaging.system']
            # net.peer.name / net.peer.port are the v1.17 fallbacks
            assert_equal attrs['net.peer.name'], agent['host']
            assert_equal attrs['net.peer.port'], agent['port']
            assert_equal attrs['messaging.rabbitmq.destination.routing_key'], agent['message.routingKey']
            # messaging.destination (legacy) flows to message.queueName
            assert_equal attrs['messaging.destination'], agent['message.queueName']
          end

          def test_consumer_v_1_17_custom_attributes
            run_consumer_span(consumer_v_1_17_attrs)

            spans = harvest_span_events!
            span = spans[1][0]
            custom = span[1]

            keys_assigned_elsewhere = %w[
              messaging.destination
              messaging.rabbitmq.destination.routing_key
              net.peer.name
              net.peer.port
            ]

            assert_empty custom.keys & keys_assigned_elsewhere
            assert_equal 'AMQP', custom['messaging.protocol']
          end

          # ---------- producer v1.30 ----------

          def test_producer_v_1_30_segment_properties
            transaction = run_producer_span(producer_v_1_30_attrs)
            segment = transaction.segments[1]

            assert_instance_of NewRelic::Agent::Transaction::MessageBrokerSegment, segment
            assert_equal 'MessageBroker/Kafka/Topic/Produce/Named/events.topic', segment.name
            assert_equal 'Kafka', segment.library
            assert_equal :topic, segment.destination_type
            assert_equal 'events.topic', segment.destination_name
            assert_equal :produce, segment.action
          end

          def test_producer_v_1_30_metrics
            run_producer_span(producer_v_1_30_attrs)

            assert_metrics_recorded([
              'MessageBroker/Kafka/Topic/Produce/Named/events.topic'
            ])
          end

          def test_producer_v_1_30_agent_attributes
            attrs = producer_v_1_30_attrs
            transaction = run_producer_span(attrs)
            segment = transaction.segments[1]
            agent = segment.attributes.agent_attributes_for(AttributeFilter::DST_TRANSACTION_TRACER)

            assert_equal attrs['messaging.system'], agent['messaging.system']
            assert_equal attrs['server.address'], agent['host']
            assert_equal attrs['server.port'], agent['port']
            # routing_key and correlation_id are on segment.params for producers
            refute agent.key?('routingKey')
            refute agent.key?('correlation_id')
          end

          def test_producer_v_1_30_segment_params
            attrs = producer_v_1_30_attrs
            transaction = run_producer_span(attrs)
            segment = transaction.segments[1]

            assert_equal attrs['messaging.kafka.message.key'], segment.params[:routing_key]
            assert_equal attrs['messaging.message.conversation_id'], segment.params[:correlation_id]
          end

          def test_producer_v_1_30_custom_attributes
            run_producer_span(producer_v_1_30_attrs)

            spans = harvest_span_events!
            span = spans[1][0]
            custom = span[1]

            keys_assigned_elsewhere = %w[
              messaging.destination.name
              messaging.kafka.message.key
              messaging.message.conversation_id
              server.address
              server.port
            ]

            assert_empty custom.keys & keys_assigned_elsewhere
            assert_equal 7, custom['messaging.kafka.partition']
          end

          # ---------- producer v1.24 ----------

          def test_producer_v_1_24_segment_properties
            transaction = run_producer_span(producer_v_1_24_attrs)
            segment = transaction.segments[1]

            assert_instance_of NewRelic::Agent::Transaction::MessageBrokerSegment, segment
            # rabbitmq producer infers :exchange when no explicit kind is set
            assert_equal 'MessageBroker/RabbitMQ/Exchange/Produce/Named/events.exchange', segment.name
            assert_equal 'RabbitMQ', segment.library
            assert_equal :exchange, segment.destination_type
            assert_equal 'events.exchange', segment.destination_name
            assert_equal :produce, segment.action
          end

          def test_producer_v_1_24_metrics
            run_producer_span(producer_v_1_24_attrs)

            assert_metrics_recorded([
              'MessageBroker/RabbitMQ/Exchange/Produce/Named/events.exchange'
            ])
          end

          def test_producer_v_1_24_agent_attributes
            attrs = producer_v_1_24_attrs
            transaction = run_producer_span(attrs)
            segment = transaction.segments[1]
            agent = segment.attributes.agent_attributes_for(AttributeFilter::DST_TRANSACTION_TRACER)

            assert_equal attrs['messaging.system'], agent['messaging.system']
            assert_equal attrs['server.address'], agent['host']
            assert_equal attrs['server.port'], agent['port']
            refute agent.key?('routingKey')
            refute agent.key?('correlation_id')
          end

          def test_producer_v_1_24_segment_params
            attrs = producer_v_1_24_attrs
            transaction = run_producer_span(attrs)
            segment = transaction.segments[1]

            assert_equal attrs['messaging.rabbitmq.destination.routing_key'], segment.params[:routing_key]
            assert_equal attrs['messaging.message.conversation_id'], segment.params[:correlation_id]
          end

          def test_producer_v_1_24_custom_attributes
            run_producer_span(producer_v_1_24_attrs)

            spans = harvest_span_events!
            span = spans[1][0]
            custom = span[1]

            keys_assigned_elsewhere = %w[
              messaging.destination.name
              messaging.rabbitmq.destination.routing_key
              messaging.message.conversation_id
              server.address
              server.port
            ]

            assert_empty custom.keys & keys_assigned_elsewhere
            assert_equal 12, custom['messaging.rabbitmq.delivery_tag']
          end

          # ---------- producer v1.17 ----------

          def test_producer_v_1_17_segment_properties
            transaction = run_producer_span(producer_v_1_17_attrs)
            segment = transaction.segments[1]

            assert_instance_of NewRelic::Agent::Transaction::MessageBrokerSegment, segment
            assert_equal 'MessageBroker/RabbitMQ/Queue/Produce/Named/events.exchange', segment.name
            assert_equal 'RabbitMQ', segment.library
            assert_equal :queue, segment.destination_type
            assert_equal 'events.exchange', segment.destination_name
            assert_equal :produce, segment.action
          end

          def test_producer_v_1_17_metrics
            run_producer_span(producer_v_1_17_attrs)

            assert_metrics_recorded([
              'MessageBroker/RabbitMQ/Queue/Produce/Named/events.exchange'
            ])
          end

          def test_producer_v_1_17_agent_attributes
            attrs = producer_v_1_17_attrs
            transaction = run_producer_span(attrs)
            segment = transaction.segments[1]
            agent = segment.attributes.agent_attributes_for(AttributeFilter::DST_TRANSACTION_TRACER)

            assert_equal attrs['messaging.system'], agent['messaging.system']
            # net.peer.name / net.peer.port are the v1.17 fallbacks
            assert_equal attrs['net.peer.name'], agent['host']
            assert_equal attrs['net.peer.port'], agent['port']
            refute agent.key?('routingKey')
            refute agent.key?('correlation_id')
          end

          def test_producer_v_1_17_segment_params
            attrs = producer_v_1_17_attrs
            transaction = run_producer_span(attrs)
            segment = transaction.segments[1]

            assert_equal attrs['messaging.rabbitmq.destination.routing_key'], segment.params[:routing_key]
            assert_equal attrs['messaging.message.conversation_id'], segment.params[:correlation_id]
          end

          def test_producer_v_1_17_custom_attributes
            run_producer_span(producer_v_1_17_attrs)

            spans = harvest_span_events!
            span = spans[1][0]
            custom = span[1]

            keys_assigned_elsewhere = %w[
              messaging.destination
              messaging.rabbitmq.destination.routing_key
              messaging.message.conversation_id
              net.peer.name
              net.peer.port
            ]

            assert_empty custom.keys & keys_assigned_elsewhere
            assert_equal 'AMQP', custom['messaging.protocol']
          end

          # ---------- consumer creates a transaction when no current transaction exists ----------

          def test_consumer_transaction_name
            # No surrounding in_transaction — consumer should create an
            # OtherTransaction with category :message and the properly-formatted
            # transaction name from Messaging.transaction_name.
            @tracer.in_span('consume', attributes: consumer_v_1_24_attrs.dup, kind: :consumer) do |span|
              # noop
            end

            txns = harvest_transaction_events!
            txn = txns[1][0]
            intrinsics = txn[0]

            assert_equal 'OtherTransaction/Message/RabbitMQ/Queue/Consume/Named/orders.queue', intrinsics['name']
          end

          def test_consumer_transaction_metrics
            @tracer.in_span('consume', attributes: consumer_v_1_24_attrs.dup, kind: :consumer) do |span|
              # noop
            end

            assert_metrics_recorded([
              'OtherTransaction/Message/RabbitMQ/Queue/Consume/Named/orders.queue',
              'OtherTransactionTotalTime'
            ])
          end

          # ---------- consumer with remote parent ----------
          # Per spec: a consumer span with a remote parent MUST create a new
          # Other transaction. NR creates it with category :message and uses
          # Messaging.transaction_name to produce the proper metric name.

          def test_consumer_with_remote_parent_creates_message_transaction
            span = @tracer.start_span(
              'consume',
              with_parent: remote_context,
              attributes: consumer_v_1_24_attrs.dup,
              kind: :consumer
            )

            assert_instance_of NewRelic::Agent::Transaction, span.finishable
            assert_equal :message, span.finishable.category

            span.finish
          end

          def test_consumer_with_remote_parent_transaction_name
            span = @tracer.start_span(
              'consume',
              with_parent: remote_context,
              attributes: consumer_v_1_24_attrs.dup,
              kind: :consumer
            )
            span.finish

            txns = harvest_transaction_events!
            txn = txns[1][0]
            intrinsics = txn[0]

            assert_equal 'OtherTransaction/Message/RabbitMQ/Queue/Consume/Named/orders.queue', intrinsics['name']
          end

          def test_consumer_with_remote_parent_metrics
            span = @tracer.start_span(
              'consume',
              with_parent: remote_context,
              attributes: consumer_v_1_24_attrs.dup,
              kind: :consumer
            )
            span.finish

            assert_metrics_recorded([
              'OtherTransaction/Message/RabbitMQ/Queue/Consume/Named/orders.queue',
              'OtherTransactionTotalTime'
            ])
          end

          # ---------- producer with remote parent ----------
          def test_producer_with_remote_parent_creates_message_transaction
            span = @tracer.start_span(
              'publish',
              with_parent: remote_context,
              attributes: producer_v_1_24_attrs.dup,
              kind: :producer
            )

            assert_instance_of NewRelic::Agent::Transaction, span.finishable
            assert_equal :message, span.finishable.category

            span.finish
          end

          def test_producer_with_remote_parent_transaction_name
            span = @tracer.start_span(
              'publish',
              with_parent: remote_context,
              attributes: producer_v_1_24_attrs.dup,
              kind: :producer
            )
            span.finish

            txns = harvest_transaction_events!
            txn = txns[1][0]
            intrinsics = txn[0]

            assert_equal 'OtherTransaction/Message/RabbitMQ/Exchange/Produce/Named/events.exchange', intrinsics['name']
          end

          def test_producer_with_remote_parent_metrics
            span = @tracer.start_span(
              'publish',
              with_parent: remote_context,
              attributes: producer_v_1_24_attrs.dup,
              kind: :producer
            )
            span.finish

            assert_metrics_recorded([
              'OtherTransaction/Message/RabbitMQ/Exchange/Produce/Named/events.exchange',
              'OtherTransactionTotalTime'
            ])
          end

          # ---------- kinesis (:stream) with remote parent ----------
          # Exercises MessagingPatch#transaction_name's :stream branch

          def test_kinesis_with_remote_parent_transaction_name
            attrs = {
              'messaging.system' => 'aws_kinesis',
              'messaging.destination.name' => 'orders-stream'
            }

            span = @tracer.start_span(
              'publish',
              with_parent: remote_context,
              attributes: attrs,
              kind: :producer
            )
            span.finish

            intrinsics = harvest_transaction_events![1][0][0]

            assert_equal 'OtherTransaction/Message/Kinesis/Stream/Produce/Named/orders-stream', intrinsics['name']
          end

          private

          def remote_context
            carrier = {
              'traceparent' => '00-da8bc8cc6d062849b0efcf3c169afb5a-7d3efb1b173fecfa-01',
              'tracestate' => ''
            }

            ::OpenTelemetry::Trace::Propagation::TraceContext::TextMapPropagator.new.extract(carrier)
          end
        end
      end
    end
  end
end
