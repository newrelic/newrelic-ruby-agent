# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    class HealthCheck
      def initialize
        NewRelic::Agent.logger.debug("INIT DEBUG: Process #{Process.pid} starting HealthCheck initialization")

        @start_time = nano_time
        @continue = true
        @status = HEALTHY

        NewRelic::Agent.logger.debug("INIT DEBUG: Process #{Process.pid} initial state - @continue = #{@continue}, @status = #{@status.inspect}")

        # the following assignments may set @continue = false if they are invalid
        NewRelic::Agent.logger.debug("INIT DEBUG: Process #{Process.pid} calling set_enabled")
        set_enabled

        NewRelic::Agent.logger.debug("INIT DEBUG: Process #{Process.pid} calling set_delivery_location")
        set_delivery_location

        NewRelic::Agent.logger.debug("INIT DEBUG: Process #{Process.pid} calling set_frequency")
        set_frequency

        NewRelic::Agent.logger.debug("INIT DEBUG: Process #{Process.pid} finished initialization - @continue = #{@continue}, @enabled = #{@enabled}")
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
        NewRelic::Agent.logger.debug("HEALTH LOOP DEBUG: Process #{Process.pid} called create_and_run_health_check_loop")

        unless health_checks_enabled?
          NewRelic::Agent.logger.debug("HEALTH LOOP DEBUG: Process #{Process.pid} health_checks_enabled? = false, returning early")
          return
        end

        unless @continue
          NewRelic::Agent.logger.debug("HEALTH LOOP DEBUG: Process #{Process.pid} @continue = false, returning early")
          return
        end

        NewRelic::Agent.logger.debug("HEALTH LOOP DEBUG: Process #{Process.pid} passed all checks, starting health check loop")
        NewRelic::Agent.record_metric('Supportability/AgentControl/Health/enabled', 1)

        Thread.new do
          while @continue
            begin
              sleep @frequency
              write_file
              @continue = false if @status == SHUTDOWN
            rescue StandardError => e
              NewRelic::Agent.logger.error("Aborting Agent Control health check. Error raised: #{e}")
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
        # DEBUG: Check what each process sees for environment variables
        control_enabled = ENV['NEW_RELIC_AGENT_CONTROL_ENABLED']
        delivery_location = ENV['NEW_RELIC_AGENT_CONTROL_HEALTH_DELIVERY_LOCATION']

        NewRelic::Agent.logger.debug("ENV DEBUG: Process #{Process.pid} sees NEW_RELIC_AGENT_CONTROL_ENABLED = '#{control_enabled}'")
        NewRelic::Agent.logger.debug("ENV DEBUG: Process #{Process.pid} sees NEW_RELIC_AGENT_CONTROL_HEALTH_DELIVERY_LOCATION = '#{delivery_location}'")

        @enabled = if ENV['NEW_RELIC_AGENT_CONTROL_ENABLED'] == 'true'
          NewRelic::Agent.logger.debug("Process #{Process.pid} enabling health checks (NEW_RELIC_AGENT_CONTROL_ENABLED = true)")
          true
        else
          NewRelic::Agent.logger.debug("Process #{Process.pid} NEW_RELIC_AGENT_CONTROL_ENABLED not true, disabling health checks")
          @continue = false
          false
        end
      end

      def set_delivery_location
        delivery_env = ENV['NEW_RELIC_AGENT_CONTROL_HEALTH_DELIVERY_LOCATION']
        NewRelic::Agent.logger.debug("DELIVERY DEBUG: Process #{Process.pid} ENV delivery location = '#{delivery_env}'")

        @delivery_location = if delivery_env
          # The spec states file paths for the delivery location will begin with file://
          # This does not create a valid path in Ruby, so remove the prefix when present
          result = delivery_env.gsub('file://', '')
          NewRelic::Agent.logger.debug("DELIVERY DEBUG: Process #{Process.pid} using env location (cleaned) = '#{result}'")
          result
        else
          # The spec default is 'file:///newrelic/apm/health', but since we're just going to remove it anyway...
          result = '/newrelic/apm/health'
          NewRelic::Agent.logger.debug("DELIVERY DEBUG: Process #{Process.pid} using default location = '#{result}'")
          result
        end

        NewRelic::Agent.logger.debug("DELIVERY DEBUG: Process #{Process.pid} final @delivery_location = '#{@delivery_location}'")
      end

      def set_frequency
        frequency_env = ENV['NEW_RELIC_AGENT_CONTROL_HEALTH_FREQUENCY']
        NewRelic::Agent.logger.debug("FREQUENCY DEBUG: Process #{Process.pid} ENV frequency = '#{frequency_env}'")

        @frequency = frequency_env ? frequency_env.to_i : 5
        NewRelic::Agent.logger.debug("FREQUENCY DEBUG: Process #{Process.pid} final @frequency = #{@frequency}")

        if @frequency <= 0
          NewRelic::Agent.logger.debug("FREQUENCY DEBUG: Process #{Process.pid} frequency #{@frequency} <= 0, disabling health checks")
          @continue = false
        else
          NewRelic::Agent.logger.debug("FREQUENCY DEBUG: Process #{Process.pid} frequency #{@frequency} > 0, keeping @continue = #{@continue}")
        end
      end

      def contents
        <<~CONTENTS
          entity_guid: #{entity_guid}
          healthy: #{@status[:healthy]}
          status: #{@status[:message]}#{last_error}
          start_time_unix_nano: #{@start_time}
          status_time_unix_nano: #{nano_time}
        CONTENTS
      end

      def entity_guid
        guid = NewRelic::Agent.config[:entity_guid]
        return guid if guid && !guid.empty?

        File.read('/tmp/nr_entity_guid').strip rescue nil
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
        @file ||= "#{@delivery_location}/#{file_name}"

        File.write(@file, contents)
      rescue StandardError => e
        NewRelic::Agent.logger.error("Agent Control health check raised an error while writing a file: #{e}")
        @continue = false
      end

      def health_checks_enabled?
        NewRelic::Agent.logger.debug("HEALTH ENABLED DEBUG: Process #{Process.pid} checking health_checks_enabled?")
        NewRelic::Agent.logger.debug("HEALTH ENABLED DEBUG: Process #{Process.pid} @enabled = #{@enabled}")
        NewRelic::Agent.logger.debug("HEALTH ENABLED DEBUG: Process #{Process.pid} @delivery_location = '#{@delivery_location}'")
        NewRelic::Agent.logger.debug("HEALTH ENABLED DEBUG: Process #{Process.pid} @frequency = #{@frequency}")

        result = @enabled && @delivery_location && @frequency > 0
        NewRelic::Agent.logger.debug("HEALTH ENABLED DEBUG: Process #{Process.pid} health_checks_enabled? = #{result}")

        result
      end

      def update_message(options)
        @status[:message] = sprintf(@status[:message], *options)
      rescue StandardError => e
        NewRelic::Agent.logger.debug("Error raised while updating Agent Control health check message: #{e}." \
          "options = #{options}, @status[:message] = #{@status[:message]}")
      end
    end
  end
end
