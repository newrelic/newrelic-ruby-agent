# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    class HealthCheck
      def initialize
        # should we pass this in as an arg from the init_plugin method call?
        @start_time = nano_time
        # if they're configs, is it worth saving them in vars?
        @fleet_id = NewRelic::Agent.config[:'superagent.fleet_id']
        @delivery_location = NewRelic::Agent.config[:'superagent.health.delivery_location']
        @frequency = NewRelic::Agent.config[:'superagent.health.frequency']
        # @check? = false
      end

      # nope out if no delivery_location?
      # seems like something for init_plugin
      def validate_delivery_location
      end

      # TODO: check health
      def health
        'health: true'
      end

      # TODO: get valid status
      def status
        'status: Agent has shutdown'
      end

      # TODO: get actual last error
      def last_error
        'last_error: NR-APM-1000'
      end

      def start_time
        "start_time_unix_nano: #{@start_time}"
      end

      def status_time
        "status_time_unix_nano: #{nano_time}"
      end

      def nano_time
        Process.clock_gettime(Process::CLOCK_REALTIME, :nanosecond)
      end

      def file_name
        "health-#{NewRelic::Agent::GuidGenerator.generate_guid(32)}.yml"
      end

      def write_file
        @path ||= find_or_create_file_path

        File.open("#{@path}/#{file_name}", 'w') do |f|
          f.write(contents) # add .to_yaml?
        end
      end

      def contents
        [health, status, last_error, status_time, start_time].join("\n")
      end

      # Adapted from AgentLogger
      # rescue?
      def find_or_create_file_path
        for abs_path in [File.expand_path(@delivery_location),
          File.expand_path(File.join('', @delivery_location))] do
          if File.directory?(abs_path) || (Dir.mkdir(abs_path) rescue nil)
            return abs_path[%r{^(.*?)/?$}]
          end
        end
        nil
      end
    end
  end
end
