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

      def synthetics?
        !!(synthetics_resource || synthetics_job || synthetics_monitor)
      end

      VERSION_KEY             = 'v'.freeze
      DATA_KEY                = 'd'.freeze
      CALLER_TYPE_KEY         = 'ty'.freeze
      CALLER_ACCOUNT_KEY      = 'ac'.freeze
      CALLER_APP_KEY          = 'ap'.freeze
      ID_KEY                  = 'id'.freeze
      TRIP_ID_KEY             = 'tr'.freeze
      DEPTH_KEY               = 'de'.freeze
      ORDER_KEY               = 'or'.freeze
      TIMESTAMP_KEY           = 'ti'.freeze
      HOST_KEY                = 'ho'.freeze
      SYNTHETICS_KEY          = 'sy'.freeze
      SYNTHETICS_RESOURCE_KEY = 'r'.freeze
      SYNTHETICS_JOB_KEY      = 'j'.freeze
      SYNTHETICS_MONITOR_KEY  = 'm'.freeze

      def to_json
        result = {
          VERSION_KEY => version
        }

        result[DATA_KEY] = {
          CALLER_TYPE_KEY    => caller_type,
          CALLER_ACCOUNT_KEY => caller_account_id,
          CALLER_APP_KEY     => caller_app_id,
          ID_KEY             => id,
          TRIP_ID_KEY        => trip_id,
          DEPTH_KEY          => depth,
          ORDER_KEY          => order,
          TIMESTAMP_KEY      => timestamp,
        }

        if synthetics?
          result[DATA_KEY][SYNTHETICS_KEY] = {
            SYNTHETICS_RESOURCE_KEY => synthetics_resource,
            SYNTHETICS_JOB_KEY      => synthetics_job,
            SYNTHETICS_MONITOR_KEY  => synthetics_monitor
          }
        end

        JSON.dump(result)
      end

      alias_method :text, :to_json

      def http_safe
        Bas64.encode64 to_json
      end
    end
  end
end
