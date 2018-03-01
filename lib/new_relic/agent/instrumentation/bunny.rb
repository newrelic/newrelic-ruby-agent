# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

DependencyDetection.defer do
  named :bunny

  depends_on do
    defined?(Bunny)
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Bunny instrumentation'
    require 'new_relic/agent/cross_app_tracing'
    require 'new_relic/agent/messaging'
    require 'new_relic/agent/transaction/message_broker_segment'
  end

  executes do
    module Bunny
      class Exchange
        alias_method :publish_without_new_relic, :publish

        def publish payload, opts = {}
          begin
            destination = NewRelic::Agent::Instrumentation::Bunny.exchange_name(name)

            tracing_enabled =
              NewRelic::Agent::CrossAppTracing.cross_app_enabled? ||
              NewRelic::Agent.config[:'distributed_tracing.enabled']
            opts[:headers] ||= {} if tracing_enabled

            segment = NewRelic::Agent::Messaging.start_amqp_publish_segment(
              library: NewRelic::Agent::Instrumentation::Bunny::LIBRARY,
              destination_name: destination,
              headers: opts[:headers],
              routing_key: opts[:routing_key] || opts[:key],
              reply_to: opts[:reply_to],
              correlation_id: opts[:correlation_id],
              exchange_type: type
            )
          rescue => e
            NewRelic::Agent.logger.error "Error starting message broker segment in Bunny::Exchange#publish", e
          end

          begin
            publish_without_new_relic payload, opts
          ensure
            segment.finish if segment
          end
        end
      end

      class Queue
        alias_method :pop_without_new_relic, :pop

        def pop(opts = {:manual_ack => false}, &block)
          t0 = Time.now
          msg = pop_without_new_relic opts, &block

          begin
            exchange_name = NewRelic::Agent::Instrumentation::Bunny.exchange_name(msg.first.exchange)

            segment = NewRelic::Agent::Messaging.start_amqp_consume_segment(
              library: NewRelic::Agent::Instrumentation::Bunny::LIBRARY,
              destination_name: exchange_name,
              delivery_info: msg[0],
              message_properties: msg[1],
              exchange_type: channel.exchanges[msg.first.exchange].type,
              queue_name: name,
              start_time: t0
            )

          rescue => e
            NewRelic::Agent.logger.error "Error starting message broker segment in Bunny::Queue#pop", e
          ensure
            segment.finish if segment
          end

          msg
        end

        alias_method :purge_without_new_relic, :purge

        def purge *args
          begin
            type = server_named? ? :temporary_queue : :queue
            segment = NewRelic::Agent::Transaction.start_message_broker_segment(
              action: :purge,
              library: NewRelic::Agent::Instrumentation::Bunny::LIBRARY,
              destination_type: type,
              destination_name: name
            )
          rescue => e
            NewRelic::Agent.logger.error "Error starting message broker segment in Bunny::Queue#purge", e
          end

          begin
            purge_without_new_relic(*args)
          ensure
            segment.finish if segment
          end
        end
      end

      class Consumer
        alias_method :call_without_new_relic, :call

        def call *args
          delivery_info, message_properties, _ = args
          queue_name = queue.respond_to?(:name) ? queue.name : queue

          NewRelic::Agent::Messaging.wrap_amqp_consume_transaction(
            library: NewRelic::Agent::Instrumentation::Bunny::LIBRARY,
            destination_name: NewRelic::Agent::Instrumentation::Bunny.exchange_name(delivery_info.exchange),
            delivery_info: delivery_info,
            message_properties: message_properties,
            exchange_type: NewRelic::Agent::Instrumentation::Bunny.exchange_type(delivery_info, channel),
            queue_name: queue_name) do

            call_without_new_relic(*args)
          end
        end
      end
    end
  end
end

module NewRelic
  module Agent
    module Instrumentation
      module Bunny
        LIBRARY = 'RabbitMQ'.freeze
        DEFAULT = 'Default'.freeze
        SLASH   = '/'.freeze

        class << self
          def exchange_name name
            name.empty? ? DEFAULT : name
          end

          def exchange_type delivery_info, channel
            if di_exchange = delivery_info[:exchange]
              return :direct if di_exchange.empty?
              return channel.exchanges[delivery_info[:exchange]].type if channel.exchanges[di_exchange]
            end
          end
        end
      end
    end
  end
end
