# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'new_relic/agent/utilization/vendor'

module NewRelic
  module Agent
    module Utilization
      class ECS < Vendor
        vendor_name 'ecs'
        endpoint ENV['ECS_CONTAINER_METADATA_URI']
        keys 'DockerId'

        def transform_key(key)
          key.prepend('ecs')
        end
      end
    end
  end
end
