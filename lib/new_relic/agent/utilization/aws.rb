# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require 'new_relic/agent/utilization/vendor'

module NewRelic
  module Agent
    module Utilization
      class AWS < Vendor
        IMDS_BASE_URL = 'http://169.254.169.254/latest'.freeze
        IMDS_KEYS = %w[instanceId instanceType availabilityZone].freeze
        IMDS_TOKEN_TTL_SECS = '60'.freeze

        class << self
          def imds_token
            uri = URI.parse("#{IMDS_BASE_URL}/api/token")
            http = Net::HTTP.new(uri.hostname)
            response = http.send_request('PUT',
              uri.path,
              '',
              {'X-aws-ec2-metadata-token-ttl-seconds' => IMDS_TOKEN_TTL_SECS})
            unless response.code == Vendor::SUCCESS
              NewRelic::Agent.logger.error 'Failed to obtain an AWS token for use with IMDS - encountered ' \
                                           "#{response.class} with HTTP response code #{response.code}"
              return
            end

            response.body
          end
        end

        vendor_name "aws"
        endpoint "#{IMDS_BASE_URL}/dynamic/instance-identity/document"
        keys IMDS_KEYS
        headers 'X-aws-ec2-metadata-token' => -> { imds_token }
        key_transforms :to_sym
      end
    end
  end
end
