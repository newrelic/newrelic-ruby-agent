# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction/segment'
require 'new_relic/agent/cross_app_tracing'

module NewRelic
  module Agent
    class Transaction
      class MessageBrokerSegment < Segment
        CONSUME  = 'Consume'.freeze
        EXCHANGE = 'Exchange'.freeze
        NAMED    = 'Named/'.freeze
        PRODUCE  = 'Produce'.freeze
        QUEUE    = 'Queue'.freeze
        PURGE    = 'Purge'.freeze
        SLASH    = '/'.freeze
        TEMP     = 'Temp'.freeze
        TOPIC    = 'Topic'.freeze
        UNKNOWN  = 'Unknown'.freeze

        EMPTY_STRING = ''.freeze

        DESTINATION_TYPES = [
          :exchange,
          :queue,
          :topic,
          :temporary_queue,
          :temporary_topic,
          :unknown
        ]

        ACTIONS = {
          consume: CONSUME,
          produce: PRODUCE,
          purge: PURGE
        }

        TYPES = {
          exchange:        EXCHANGE,
          temporary_queue: QUEUE,
          queue:           QUEUE,
          topic:           TOPIC,
          unknown:         EXCHANGE
        }

        METRIC_PREFIX      = 'MessageBroker/'.freeze

        class << self
          def obfuscator
            @obfuscator ||= NewRelic::Agent::Obfuscator.new(NewRelic::Agent.config[:encoding_key])
          end
        end

        attr_reader :action,
                    :destination_name,
                    :destination_type,
                    :library,
                    :message_properties

        def initialize action: nil,
                       library: nil,
                       destination_type: nil,
                       destination_name: nil,
                       message_properties: nil,
                       parameters: nil,
                       start_time: nil

          # ruby 2.0.0 does not support required kwargs
          raise ArgumentError, 'missing required argument: action' if action.nil?
          raise ArgumentError, 'missing required argument: library' if library.nil?
          raise ArgumentError, 'missing required argument: destination_type' if destination_type.nil?
          raise ArgumentError, 'missing required argument: destination_name' if destination_name.nil?

          @action = action
          @library = library
          @destination_type = destination_type
          @destination_name = destination_name
          @message_properties = message_properties
          super(nil, nil, start_time)
          params.merge! parameters if parameters
        end

        def obfuscator
          self.class.obfuscator
        end

        def name
          return @name if @name
          @name = METRIC_PREFIX + library
          @name << SLASH << TYPES[destination_type] << SLASH << ACTIONS[action] << SLASH

          if destination_type == :temporary_queue || destination_type == :temporary_topic
            @name << TEMP
          else
            @name << NAMED << destination_name
          end

          @name
        end

        def transaction= t
          super
          return unless message_properties
          case action
          when :produce
            produce_message_headers
          when :consume
            consume_message_headers
          end
        rescue => e
          NewRelic::Agent.logger.error "Error during message header processing", e
        end

        private

        def produce_message_headers
          return unless record_metrics? && CrossAppTracing.cross_app_enabled?
          transaction.add_message_cat_headers message_properties if transaction
        rescue => e
          NewRelic::Agent.logger.error "Error in produce_message_headers", e
        end

        def consume_message_headers
          return unless record_metrics? && CrossAppTracing.cross_app_enabled?

          if CrossAppTracing.message_has_crossapp_request_header? message_properties
            decode_id
            decode_txn_info
            assign_synthetics_header
            assign_transaction_attributes
          end
        rescue => e
          NewRelic::Agent.logger.error "Error in consume_message_headers", e
        end

        def decode_id
          encoded_id = message_properties[NewRelic::Agent::CrossAppTracing::NR_MESSAGE_BROKER_ID_HEADER]
          decoded_id = if encoded_id.nil?
                         EMPTY_STRING
                       else
                         obfuscator.deobfuscate(encoded_id)
                       end
          if NewRelic::Agent::CrossAppTracing.valid_cross_app_id? decoded_id
            transaction_state.client_cross_app_id = decoded_id
            append_unscoped_metric "ClientApplication/#{decoded_id}/all"
          end
        end

        def decode_txn_info
          txn_header = message_properties[NewRelic::Agent::CrossAppTracing::NR_MESSAGE_BROKER_TXN_HEADER]
          begin
            txn_info = ::JSON.load(obfuscator.deobfuscate(txn_header))
            transaction_state.referring_transaction_info = txn_info
          rescue => e
            NewRelic::Agent.logger.debug("Failure deserializing encoded header in #{self.class}, #{e.class}, #{e.message}")
            nil
          end
        end

        def assign_synthetics_header
          if synthetics_header = message_properties[NewRelic::Agent::CrossAppTracing::NR_MESSAGE_BROKER_SYNTHETICS_HEADER]
            transaction.raw_synthetics_header = synthetics_header
          end
        end

        def assign_transaction_attributes
          if transaction_state.client_cross_app_id
            transaction.attributes.add_intrinsic_attribute(:client_cross_process_id, transaction_state.client_cross_app_id)
          end

          if referring_guid = transaction_state.referring_transaction_info && transaction_state.referring_transaction_info[0]
            transaction.attributes.add_intrinsic_attribute(:referring_transaction_guid, referring_guid)
          end
        end
      end
    end
  end
end
