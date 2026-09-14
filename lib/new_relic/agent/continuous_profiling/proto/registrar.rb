# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'google/protobuf'

module NewRelic
  module Agent
    module ContinuousProfiling
      module Proto
        # Other gems (e.g. opentelemetry-exporter-otlp) vendor these same proto files, and the
        # process-wide DescriptorPool raises on a duplicate registration -- route through here.
        module Registrar
          def self.register_once(pool, descriptor_data, anchor_message_name)
            return if pool.lookup(anchor_message_name)

            pool.add_serialized_file(descriptor_data)
          end
        end
      end
    end
  end
end
