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
            opts[:headers] ||= {}

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
          msg = pop_without_new_relic opts, &block

          begin
            require 'pry-byebug'; binding.pry
            exchange_name = NewRelic::Agent::Instrumentation::Bunny.exchange_name(msg.first.exchange)

            # msg[1] is an immutable MessageProperties instance that mimics a Hash interface
            # to_hash here so that we can update the headers and sneakily remove any CAT key/values
            # N.B. this then requires that all subsequent usage uses Hash accessors
            non_cat_message_properties = msg[1].to_hash
            non_cat_message_properties[:headers] = NewRelic::Agent::CrossAppTracing.reject_cat_headers non_cat_message_properties[:headers]

            segment = NewRelic::Agent::Messaging.start_amqp_consume_segment(
              library: NewRelic::Agent::Instrumentation::Bunny::LIBRARY,
              destination_name: exchange_name,
              delivery_info: msg[0],
              message_properties: non_cat_message_properties,
              exchange_type: channel.exchanges[msg.first.exchange].type,
              queue_name: name
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
          segment = nil
          txn_started = false
          state = nil

          begin
            state = NewRelic::Agent::TransactionState.tl_get
            unless state.current_transaction
              txn_name = NewRelic::Agent::Instrumentation::Bunny.transaction_name delivery_info.exchange,
                                                                                  delivery_info.routing_key
              NewRelic::Agent::Transaction.start state, :background, transaction_name: txn_name
              txn_started = true
            end

            segment = NewRelic::Agent::Messaging.start_amqp_consume_segment(
                library: NewRelic::Agent::Instrumentation::Bunny::LIBRARY,
                destination_name: NewRelic::Agent::Instrumentation::Bunny.exchange_name(delivery_info.exchange),
                delivery_info: delivery_info,
                message_properties: message_properties,
                exchange_type: channel.exchanges[delivery_info.exchange] && channel.exchanges[delivery_info.exchange].type,
                queue_name: queue.name,
                subscribed: true
              )
          rescue => e
            NewRelic::Agent.logger.error "Error starting message broker segment in Bunny consumer", e
          end

          begin
            call_without_new_relic(*args)
          ensure
            segment.finish if segment
            NewRelic::Agent::Transaction.stop(state) if state && txn_started
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

          def transaction_name exchange_name, destination_type, routing_key = nil
            transaction_name = NewRelic::Agent::Transaction::MESSAGE_PREFIX +
                               NewRelic::Agent::Instrumentation::Bunny::LIBRARY
            transaction_name << SLASH
            transaction_name << NewRelic::Agent::Transaction::MessageBrokerSegment::EXCHANGE
            transaction_name << SLASH
            transaction_name << NewRelic::Agent::Transaction::MessageBrokerSegment::NAMED
            transaction_name << self.exchange_name(exchange_name)
            transaction_name
          end
        end
      end
    end
  end
end
