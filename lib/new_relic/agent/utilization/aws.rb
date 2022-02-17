# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require 'new_relic/agent/utilization/vendor'

module NewRelic
  module Agent
    module Utilization
      class AWS < Vendor
        vendor_name "aws"
        endpoint "http://169.254.169.254/2016-09-02/dynamic/instance-identity/document"
        keys ["instanceId", "instanceType", "availabilityZone"]
        key_transforms :to_sym

        def token_prehook
          Timeout.timeout 1 do
            response = nil
            Net::HTTP.start endpoint.host, endpoint.port do |http|
              req = Net::HTTP::Put.new "http://169.254.169.254/latest/api/token", "X-aws-ec2-metadata-token-ttl-seconds" => "21600" 
              response = http.request req
              if response != nil
                @headers = {"X-aws-ec2-metadata-token" => response.body}
              end
            end
            response
          rescue
            NewRelic::Agent.logger.debug "#{vendor_name} environment not detected"
          end
        end
      end
    end
  end
end
