# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.


module NewRelic 
  module Agent 
    module Instrumentation
      module BunnyPrepend

        module Bunny
          class Exchange
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
                super
              else
                NewRelic::Agent::Tracer.capture_segment_error segment do
                  super
                end
              ensure
                segment.finish if segment
              end
            end
          end
    
          class Queue
            def pop(opts = {:manual_ack => false}, &block)
              bunny_error, delivery_info, message_properties, _payload = nil, nil, nil, nil
              begin
                t0 = Time.now
                msg = super
                delivery_info, message_properties, _payload = msg
              rescue StandardError => error
                bunny_error = error
              end
    
              begin
                exchange_name, exchange_type = if delivery_info
                  [ NewRelic::Agent::Instrumentation::Bunny.exchange_name(delivery_info.exchange),
                    NewRelic::Agent::Instrumentation::Bunny.exchange_type(delivery_info, channel) ]
                else
                  [ NewRelic::Agent::Instrumentation::Bunny.exchange_name(NewRelic::EMPTY_STR),
                    NewRelic::Agent::Instrumentation::Bunny.exchange_type({}, channel) ]
                end
    
                segment = NewRelic::Agent::Messaging.start_amqp_consume_segment(
                  library: NewRelic::Agent::Instrumentation::Bunny::LIBRARY,
                  destination_name: exchange_name,
                  delivery_info: (delivery_info || {}),
                  message_properties: (message_properties || {headers: {}}),
                  exchange_type: exchange_type,
                  queue_name: name,
                  start_time: t0
                )
              rescue => e
                NewRelic::Agent.logger.error "Error starting message broker segment in Bunny::Queue#pop", e
              else
                if bunny_error
                  segment.notice_error bunny_error
                  raise bunny_error
                end
              ensure
                segment.finish if segment
              end
    
              msg
            end
    
            def purge *args
              begin
                type = server_named? ? :temporary_queue : :queue
                segment = NewRelic::Agent::Tracer.start_message_broker_segment(
                  action: :purge,
                  library: NewRelic::Agent::Instrumentation::Bunny::LIBRARY,
                  destination_type: type,
                  destination_name: name
                )
              rescue => e
                NewRelic::Agent.logger.error "Error starting message broker segment in Bunny::Queue#purge", e
                super
              else
                NewRelic::Agent::Tracer.capture_segment_error segment do
                  super
                end
              ensure
                segment.finish if segment
              end
            end
    
          end
    
          class Consumer
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
    
                super
              end
            end
    
          end
        end
      end
    end
  end
end







