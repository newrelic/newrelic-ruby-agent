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
                     :message_properties,
                     :parameters

        def initialize action:, library:, destination_type:, destination_name:, message_properties: nil, parameters: nil
          @action = action
          @library = library
          @destination_type = destination_type
          @destination_name = destination_name
          @message_properties = message_properties
          @parameters = parameters
          super()
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
      end
    end
  end
end
