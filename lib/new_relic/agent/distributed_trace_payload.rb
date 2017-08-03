# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class DistributedTracePayload
      VERSION =[2, 0]
      CALLER_TYPE = "App".freeze
      POUND = '#'.freeze

      attr_accessor :data,
                    :id,
                    :tripId,
                    :synthetics,
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
