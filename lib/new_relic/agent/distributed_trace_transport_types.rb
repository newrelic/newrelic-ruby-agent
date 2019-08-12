# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module DistributedTraceTransportTypes
      extend self

      UNKNOWN = 'Unknown'.freeze

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

      URL_SCHEMES = {
        'http'  => 'HTTP'.freeze,
        'https' => 'HTTPS'.freeze
      }

      RACK_URL_SCHEME = 'rack.url_scheme'.freeze

      def from value
        return value if ALLOWABLE_TRANSPORT_TYPES.include?(value)

        UNKNOWN
      end


      def for_rack_request request
        URL_SCHEMES[request[RACK_URL_SCHEME]]
      end
    end
  end
end