# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class AWSInfo
      attr_reader :instance_type, :instance_id, :availability_zone

      def initialize
        load_remote_data
      end

      protected

      def load_remote_data
        handle_remote_calls do
          @instance_type = remote_fetch('instance-type')
          @instance_id = remote_fetch('instance-id')
          @availability_zone = remote_fetch('placement/availability-zone')
        end
      end

      def reset
        @instance_type = @instance_id = @availability_zone = nil
      end

      REMOTE_DATA_VALID_CHARS = /^[0-9a-zA-Z_ .\/-]$/.freeze
      INSTANCE_HOST = '169.254.169.254'
      API_VERSION   = '2008-02-01'

      def remote_fetch(remote_key)
        uri = URI("http://#{INSTANCE_HOST}/#{API_VERSION}/meta-data/#{remote_key}")
        request = Net::HTTP::get(uri)

        data = validate_remote_data(request)

        if request && data.nil?
          NewRelic::Agent.increment_metric('Supportability/utilization/aws/error')
          NewRelic::Agent.logger.warn("Fetching instance metadata for #{remote_key.inspect} returned invalid data: #{request.inspect}")
        end

        data
      end

      def handle_remote_calls
        begin
          Timeout::timeout(1) do
            yield
          end
        rescue Timeout::Error
          handle_error "UtilizationData timed out fetching remote keys."
        rescue StandardError, LoadError => e
          handle_error "UtilizationData encountered error fetching remote keys:\n#{e}"
        end
        nil
      end

      def handle_error(message)
        NewRelic::Agent.logger.debug message
        reset
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