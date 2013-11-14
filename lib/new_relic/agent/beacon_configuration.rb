# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    # This class contains the configuration data for setting up RUM
    # headers and footers - acts as a cache of this data so we don't
    # need to look it up or reconfigure it every request
    class BeaconConfiguration

      # RUM footer command used for 'finish' - based on whether JSONP is
      # being used. 'nrfj' for JSONP, otherwise 'nrf2'
      attr_reader :finish_command

      # Creates a new browser configuration data. Argument is a hash
      # of configuration values from the server
      def initialize
        ::NewRelic::Agent.logger.debug("JS agent loader version: #{Agent.config[:'browser_monitoring.loader_version']}")

        if Agent.config[:'rum.jsonp']
          ::NewRelic::Agent.logger.debug("Real User Monitoring is using JSONP protocol")
          @finish_command = 'nrfj'
        else
          @finish_command = 'nrf2'
        end

        if !Agent.config[:'rum.enabled']
          ::NewRelic::Agent.logger.debug("Real User Monitoring is disabled for this agent. Edit your configuration to change this.")
        end
      end

      def enabled?
        Agent.config[:'rum.enabled'] && !!Agent.config[:beacon]
      end

      # returns a memoized version of the bytes in the license key for
      # obscuring transaction names in the javascript
      def license_bytes
        if @license_bytes.nil?
          @license_bytes = []
          Agent.config[:license_key].each_byte {|byte| @license_bytes << byte}
        end
        @license_bytes
      end
    end
  end
end
