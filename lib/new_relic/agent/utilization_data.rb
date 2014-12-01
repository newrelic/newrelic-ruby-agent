# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class UtilizationData

      REMOTE_DATA_VALID_CHARS = /^[0-9a-zA-Z_ .\/-]$/.freeze

      def harvest!
        [hostname, container_id, cpu_count, instance_type]
      end

      # No persistent data, so no need for merging or resetting
      def merge!(*_); end
      def reset!(*_); end

      def hostname
        NewRelic::Agent::Hostname.get
      end

      def container_id
        ::NewRelic::Agent::SystemInfo.docker_container_id
      end

      def cpu_count
        ::NewRelic::Agent::SystemInfo.clear_processor_info
        ::NewRelic::Agent::SystemInfo.num_logical_processors
      end

      def instance_type
        Timeout::timeout(1) do
          remote_fetch('instance-type')
        end
      rescue Timeout::Error
        NewRelic::Agent.logger.debug("UtilizationData timed out fetching remote keys.")
        nil
      rescue StandardError, LoadError => e
        NewRelic::Agent.logger.debug("UtilizationData encountered error fetching remote keys:\n#{e}")
        nil
      end

      INSTANCE_HOST = '169.254.169.254'
      API_VERSION   = '2008-02-01'

      def remote_fetch(remote_key)
        uri = URI("http://#{INSTANCE_HOST}/#{API_VERSION}/meta-data/#{remote_key}")
        request = Net::HTTP::get(uri)

        data = validate_remote_data(request)

        if request && data.nil?
          NewRelic::Agent.logger.warn("Fetching instance metadata for #{remote_key.inspect} returned invalid data: #{request.inspect}")
        end

        data
      end

      def validate_remote_data(data_str)
        return nil unless data_str.kind_of?(String)
        return nil unless data_str.size <= 255

        data_str.each_char do |ch|
          next if ch =~ REMOTE_DATA_VALID_CHARS
          code_point = ch[0].ord # this works in Ruby 1.8.7 - 2.1.2
          next if code_point >= 0x80

          return nil # it's in neither set of valid characters
        end

        data_str
      end

    end
  end
end
