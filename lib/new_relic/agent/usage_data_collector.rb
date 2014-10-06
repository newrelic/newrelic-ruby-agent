# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent

    module UsageDataCollector

      REMOTE_DATA_VALID_CHARS = /^[0-9a-zA-Z_ .\/-]$/.freeze

      def self.gather_usage_data
        ::NewRelic::Agent::SystemInfo.clear_processor_info

        data = {
          'logicalProcessors' => ::NewRelic::Agent::SystemInfo.num_logical_processors,
          'physicalCores'     => ::NewRelic::Agent::SystemInfo.num_physical_cores,
          'physicalPackages'  => ::NewRelic::Agent::SystemInfo.num_physical_packages
        }

        begin
          Timeout::timeout(1) do
            keys_for_names = {
              'instanceType' => 'instance-type',
              'dataCenter'   => 'placement/availability-zone',
              'instanceId'   => 'instance-id'
            }

            keys_for_names.each do |name, key|
              data[name] = remote_fetch(key)
            end
          end
        rescue Timeout::Error
          NewRelic::Agent.logger.debug("UsageDataCollector timed out fetching remote keys.")
        rescue StandardError, LoadError => e
          NewRelic::Agent.logger.debug("UsageDataCollector encountered error fetching remote keys:\n#{e}")
        end

        Hash[data.select{|k,v| v}] # filter out falsey values
      end

      def self.remote_fetch(remote_key)
        host        = '169.254.169.254'
        api_version = '2008-02-01'

        uri = URI("http://#{host}/#{api_version}/meta-data/#{remote_key}")
        request = Net::HTTP::get(uri)

        data = validate_remote_data(request)

        if request && data.nil?
          NewRelic::Agent.logger.warn("Fetching instance metadata for #{remote_key.inspect} returned invalid data: #{request.inspect}")
        end

        data
      end

      def self.validate_remote_data(data_str)
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
