# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    class HealthCheck
      def initialize
        @start_time = nano_time
        @continue = true
        @status = HEALTHY
        # the following assignments may set @continue = false if they are invalid
        set_enabled
        set_delivery_location
        set_frequency
      end

      HEALTHY = {healthy: true, last_error: 'NR-APM-000', message: 'Healthy'}.freeze
      INVALID_LICENSE_KEY = {healthy: false, last_error: 'NR-APM-001', message: 'Invalid license key (HTTP status code 401)'}.freeze
      MISSING_LICENSE_KEY = {healthy: false, last_error: 'NR-APM-002', message: 'License key missing in configuration'}.freeze
      FORCED_DISCONNECT = {healthy: false, last_error: 'NR-APM-003', message: 'Forced disconnect received from New Relic (HTTP status code 410)'}.freeze
      HTTP_ERROR = {healthy: false, last_error: 'NR-APM-004', message: 'HTTP error response code [%s] recevied from New Relic while sending data type [%s]'}.freeze
      MISSING_APP_NAME = {healthy: false, last_error: 'NR-APM-005', message: 'Missing application name in agent configuration'}.freeze
      APP_NAME_EXCEEDED = {healthy: false, last_error: 'NR-APM-006', message: 'The maximum number of configured app names (3) exceeded'}.freeze
      PROXY_CONFIG_ERROR = {healthy: false, last_error: 'NR-APM-007', message: 'HTTP Proxy configuration error; response code [%s]'}.freeze
      AGENT_DISABLED = {healthy: false, last_error: 'NR-APM-008', message: 'Agent is disabled via configuration'}.freeze
      FAILED_TO_CONNECT = {healthy: false, last_error: 'NR-APM-009', message: 'Failed to connect to New Relic data collector'}.freeze
      FAILED_TO_PARSE_CONFIG = {healthy: false, last_error: 'NR-APM-010', message: 'Agent config file is not able to be parsed'}.freeze
      SHUTDOWN = {healthy: true, last_error: 'NR-APM-099', message: 'Agent has shutdown'}.freeze

      def create_and_run_health_check_loop
        return unless health_checks_enabled? && @continue

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

        @status = status.dup
        update_message(options) unless options.empty?
      end

      def healthy?
        @status == HEALTHY
      end

      private

      def set_enabled
        @enabled = if ENV['NEW_RELIC_AGENT_CONTROL_ENABLED'] == 'true'
          true
        else
          NewRelic::Agent.logger.debug('NEW_RELIC_AGENT_CONTROL_ENABLED not true, disabling health checks')
          @continue = false
          false
        end
      end

      def set_delivery_location
        @delivery_location = if ENV['NEW_RELIC_AGENT_CONTROL_HEALTH_DELIVERY_LOCATION']
          # The spec states file paths for the delivery location will begin with file://
          # This does not create a valid path in Ruby, so remove the prefix when present
          ENV['NEW_RELIC_AGENT_CONTROL_HEALTH_DELIVERY_LOCATION']&.gsub('file://', '')
        else
          NewRelic::Agent.logger.debug('NEW_RELIC_AGENT_CONTROL_HEALTH_DELIVERY_LOCATION not found, disabling health checks')
          @continue = false
          nil
        end
      end

      def set_frequency
        @frequency = ENV['NEW_RELIC_AGENT_CONTROL_HEALTH_FREQUENCY'] ? ENV['NEW_RELIC_AGENT_CONTROL_HEALTH_FREQUENCY'].to_i : 5

        if @frequency <= 0
          NewRelic::Agent.logger.debug('NEW_RELIC_AGENT_CONTROL_HEALTH_FREQUENCY zero or less, disabling health checks')
          @continue = false
        end
      end

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

      def health_checks_enabled?
        @enabled && @delivery_location && @frequency > 0
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
