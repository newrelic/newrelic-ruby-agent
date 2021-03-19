# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'bunny/chain'
require_relative 'bunny/prepend'

DependencyDetection.defer do
  named :bunny

  depends_on do
    defined?(Bunny)
  end

  depends_on do 
    allowed_by_config?
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Bunny instrumentation'
    require 'new_relic/agent/distributed_tracing/cross_app_tracing'
    require 'new_relic/agent/messaging'
    require 'new_relic/agent/transaction/message_broker_segment'
  end

  executes do
    if use_prepend?
      prepend_instrument ::Bunny::Exchange, ::NewRelic::Agent::Instrumentation::Bunny::ExchangePrepend
      prepend_instrument ::Bunny::Queue, ::NewRelic::Agent::Instrumentation::Bunny::QueuePrepend
      prepend_instrument ::Bunny::Consumer, ::NewRelic::Agent::Instrumentation::Bunny::ConsumerPrepend
    else
      chain_instrument NewRelic::Agent::Instrumentation::Bunny
    end
  end
end

module NewRelic
  module Agent
    module Instrumentation
      module Bunny
        LIBRARY = 'RabbitMQ'
        DEFAULT_NAME = 'Default'
        DEFAULT_TYPE = :direct

        SLASH   = '/'

        class << self
          def exchange_name name
            name.empty? ? DEFAULT_NAME : name
          end

          def exchange_type delivery_info, channel
            if di_exchange = delivery_info[:exchange]
              return DEFAULT_TYPE if di_exchange.empty?
              return channel.exchanges[delivery_info[:exchange]].type if channel.exchanges[di_exchange]
            end
          end
        end
      end
    end
  end
end
