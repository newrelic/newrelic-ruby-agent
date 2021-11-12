# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require 'new_relic/agent/utilization/vendor'

module NewRelic
  module Agent
    module Utilization
      class PCF < Vendor
        vendor_name 'pcf'
        keys %w[CF_INSTANCE_GUID CF_INSTANCE_IP MEMORY_LIMIT]
        key_transforms %i[downcase to_sym]

        def detect
          return false unless pcf_keys_present?

          process_response ENV
        rescue StandardError
          NewRelic::Agent.logger.error "Error occurred detecting: #{vendor_name}", e
          record_supportability_metric
          false
        end

        def pcf_keys_present?
          !(ENV.keys & keys).empty?
        end
      end
    end
  end
end
