# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/transaction/segment'
#require 'new_relic/agent/transaction/segment/cross_app_segment'

module NewRelic
  module Agent
    class Transaction
      class MessageBrokerSegment < Segment
        CONSUME  = 'Consume'.freeze
        EXCHANGE = 'Exchange'.freeze
        NAMED    = 'Named/'.freeze
        PRODUCE  = 'Produce'.freeze
        QUEUE    = 'Queue'.freeze
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
          produce: PRODUCE
        }

        TYPES = {
          exchange: EXCHANGE,
          queue:    QUEUE,
          topic:    TOPIC,
          unknown:  EXCHANGE
        }

        METRIC_PREFIX      = 'MessageBroker/'.freeze
        TRANSACTION_PREFIX = 'OtherTransaction/Message/'.freeze

         attr_reader :action,
                     :destination_name,
                     :destination_type,
                     :library,
                     :message_properties

        def initialize action:, library:, destination_type:, destination_name:, message_properties: nil, parameters: nil
          @action = action
          @library = library
          @destination_type = destination_type
          @destination_name = destination_name
          @message_properties = message_properties
          super()
          params.merge! parameters if parameters
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
          # when :consume
          #   consume_message_headers
          end
        rescue => e
          NewRelic::Agent.logger.error "Error during message header processsing", e
        end

        private

        def produce_message_headers
          return unless record_metrics? && CrossAppTracing.cross_app_enabled?
          transaction.add_message_cat_headers message_properties if transaction
        rescue => e
          NewRelic::Agent.logger.error "Error in produce_message_headers", e
        end
      end
    end
  end
end
