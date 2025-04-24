# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'new_relic/agent/utilization/vendor'

module NewRelic
  module Agent
    module Utilization
      class ECSV4 < Vendor
        vendor_name 'ecs'
        endpoint ENV['ECS_CONTAINER_METADATA_URI_V4']
        keys 'ecsDockerId'
        # headers ''
        # key_transforms :to_sym

       
      end
    end
  end
end
