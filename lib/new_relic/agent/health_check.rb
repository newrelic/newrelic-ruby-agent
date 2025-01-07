# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    class HealthCheck
      def initialize
        @start_time = nano_time
        @fleet_id = ENV['NEW_RELIC_AGENT_CONTROL_FLEET_ID']
        # The spec states file paths for the delivery location will begin with file://
        # This does not create a valid path in Ruby, so remove the prefix when present
        @delivery_location = ENV['NEW_RELIC_AGENT_CONTROL_HEALTH_DELIVERY_LOCATION']&.gsub('file://', '')
        @frequency = ENV['NEW_RELIC_AGENT_CONTROL_HEALTH_FREQUENCY'] ? ENV['NEW_RELIC_AGENT_CONTROL_HEALTH_FREQUENCY'].to_i : 5
        @continue = true
        @status = HEALTHY
      end

      HEALTHY = {healthy: true, last_error: 'NR-APM-000', message: 'Healthy'}
      INVALID_LICENSE_KEY = {healthy: false, last_error: 'NR-APM-001', message: 'Invalid liense key (HTTP status code 401)'}
      MISSING_LICENSE_KEY = {healthy: false, last_error: 'NR-APM-002', message: 'License key missing in configuration'}
      FORCED_DISCONNECT = {healthy: false, last_error: 'NR-APM-003', message: 'Forced disconnect received from New Relic (HTTP status code 410)'}
      HTTP_ERROR = {healthy: false, last_error: 'NR-APM-004', message: 'HTTP error response code [%s] recevied from New Relic while sending data type [%s]'}
      MISSING_APP_NAME = {healthy: false, last_error: 'NR-APM-005', message: 'Missing application name in agent configuration'}
      APP_NAME_EXCEEDED = {healthy: false, last_error: 'NR-APM-006', message: 'The maximum number of configured app names (3) exceeded'}
      PROXY_CONFIG_ERROR = {healthy: false, last_error: 'NR-APM-007', message: 'HTTP Proxy configuration error; response code [%s]'}
      AGENT_DISABLED = {healthy: false, last_error: 'NR-APM-008', message: 'Agent is disabled via configuration'}
      FAILED_TO_CONNECT = {healthy: false, last_error: 'NR-APM-009', message: 'Failed to connect to New Relic data collector'}
      FAILED_TO_PARSE_CONFIG = {healthy: false, last_error: 'NR-APM-010', message: 'Agent config file is not able to be parsed'}
      SHUTDOWN = {healthy: true, last_error: 'NR-APM-099', message: 'Agent has shutdown'}

      def create_and_run_health_check_loop
        unless health_check_enabled?
          @continue = false
        end

        return NewRelic::Agent.logger.debug('NEW_RELIC_AGENT_CONTROL_FLEET_ID not found, skipping health checks') unless @fleet_id
        return NewRelic::Agent.logger.debug('NEW_RELIC_AGENT_CONTROL_HEALTH_DELIVERY_LOCATION not found, skipping health checks') unless @delivery_location
        return NewRelic::Agent.logger.debug('NEW_RELIC_AGENT_CONTROL_HEALTH_FREQUENCY zero or less, skipping health checks') unless @frequency > 0

        NewRelic::Agent.logger.debug('Agent control health check conditions met. Starting health checks.')
        NewRelic::Agent.record_metric('Supportability/AgentControl/Health/enabled', 1)

        Thread.new do
          while @continue
            begin
              sleep @frequency
              write_file
              @continue = false if @status == SHUTDOWN
            rescue StandardError => e
              NewRelic::Agent.logger.error("Aborting agent control health check. Error raised: #{e}")
              @continue = false
            end
          end
        end
      end

      def update_status(status, options = [])
        return unless @continue

        @status = status
        update_message(options) unless options.empty?
      end

      private

      def contents
        <<~CONTENTS
          healthy: #{@status[:healthy]}
          status: #{@status[:message]}#{last_error}
          start_time_unix_nano: #{@start_time}
          status_time_unix_nano: #{nano_time}
        CONTENTS
      end

      def last_error
        @status[:healthy] ? '' : "\nlast_error: #{@status[:last_error]}"
      end

      def nano_time
        Process.clock_gettime(Process::CLOCK_REALTIME, :nanosecond)
      end

      def file_name
        "health-#{NewRelic::Agent::GuidGenerator.generate_guid(32)}.yml"
      end

      def write_file
        @file ||= "#{create_file_path}/#{file_name}"

        File.write(@file, contents)
      rescue StandardError => e
        NewRelic::Agent.logger.error("Agent control health check raised an error while writing a file: #{e}")
        @continue = false
      end

      def create_file_path
        for abs_path in [File.expand_path(@delivery_location),
          File.expand_path(File.join('', @delivery_location))] do
          if File.directory?(abs_path) || (Dir.mkdir(abs_path) rescue nil)
            return abs_path[%r{^(.*?)/?$}]
          end
        end
        nil
      rescue StandardError => e
        NewRelic::Agent.logger.error(
          'Agent control health check raised an error while finding or creating the file path defined in ' \
          "NEW_RELIC_AGENT_CONTROL_HEALTH_DELIVERY_LOCATION: #{e}"
        )
        @continue = false
      end

      def health_check_enabled?
        @fleet_id && @delivery_location && (@frequency > 0)
      end

      def update_message(options)
        @status[:message] = sprintf(@status[:message], *options)
      rescue StandardError => e
        NewRelic::Agent.logger.debug("Error raised while updating agent control health check message: #{e}." \
          "Reverting to original message. options = #{options}, @status[:message] = #{@status[:message]}")
      end
    end
  end
end
