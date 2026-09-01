# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'google/protobuf'

module NewRelic
  module Agent
    module ContinuousProfiling
      module Proto
        # Other gems (e.g. opentelemetry-exporter-otlp) vendor these same proto files at
        # the same paths. Google::Protobuf::DescriptorPool is a single process-wide
        # global that raises `duplicate file name` if a file is registered twice, so
        # guard every registration through here instead of calling add_serialized_file
        # directly.
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
