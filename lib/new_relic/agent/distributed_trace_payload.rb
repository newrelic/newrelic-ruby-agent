# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
require 'json'
require 'base64'

module NewRelic
  module Agent
    class DistributedTracePayload
      VERSION =[2, 0]
      CALLER_TYPE = "App".freeze
      POUND = '#'.freeze

      class << self
        def for transaction, uri=nil
          payload = new
          return payload unless payload.connected?

          payload.id = transaction.guid
          payload.trip_id = transaction.distributed_tracing_trip_id
          payload.depth = transaction.depth
          payload.order = transaction.order
          payload.host = uri.host if uri

          if transaction.synthetics_payload
            payload.synthetics_resource = transaction.synthetics_payload[2]
            payload.synthetics_job = transaction.synthetics_payload[3]
            payload.synthetics_monitor = transaction.synthetics_payload[4]
          end

          #todo:
          # handle order, depth

          payload
        end
      end

      attr_accessor :id,
                    :trip_id,
                    :synthetics_resource,
                    :synthetics_job,
                    :synthetics_monitor,
                    :order,
                    :depth,
                    :host

      attr_reader  :caller_account_id,
                   :caller_app_id,
                   :timestamp

      def initialize
        # We should return a valid DistributedTracePayload will all fields nil
        # if we haven't connected
        return unless connected?

        @caller_account_id = Agent.config[:cross_process_id].split(POUND).first
        @caller_app_id = Agent.config[:application_id]
        @timestamp = Time.now.to_f
      end

      def version
        VERSION
      end

      def caller_type
        CALLER_TYPE
      end

      # We use the presence of the cross_process_id in the config to tell if we
      # have connected yet.
      def connected?
        !!Agent.config[:'cross_process_id']
      end
    end
  end
end
