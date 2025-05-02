# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'new_relic/agent/utilization/vendor'

module NewRelic
  module Agent
    module Utilization
      class ECSV4 < Vendor
        vendor_name 'ecs_v4'
        endpoint ENV['ECS_CONTAINER_METADATA_URI_V4']
        headers 'Metadata' => 'true'
        keys %w[DockerId]

        def transform_key(key)
          'ecs' + key
        end
      end
    end
  end
end
