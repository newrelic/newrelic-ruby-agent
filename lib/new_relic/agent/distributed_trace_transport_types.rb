# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module DistributedTraceTransportTypes
      extend self

      PARENT_TRANSPORT_TYPE_UNKNOWN = 'Unknown'.freeze

      ALLOWABLE_TRANSPORT_TYPES = Set.new(%w[
        Unknown
        HTTP
        HTTPS
        Kafka
        JMS
        IronMQ
        AMQP
        Queue
        Other
      ]).freeze

      def valid_transport_type_for(value)
        return value if ALLOWABLE_TRANSPORT_TYPES.include?(value)

        PARENT_TRANSPORT_TYPE_UNKNOWN
      end
    end
  end
end