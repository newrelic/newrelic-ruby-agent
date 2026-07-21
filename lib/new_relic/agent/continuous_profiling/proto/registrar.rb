# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'google/protobuf'

module NewRelic
  module Agent
    module ContinuousProfiling
      module Proto
        # The OpenTelemetry profiles proto files vendored alongside this file are also
        # vendored, under the same file paths, by other gems in the ecosystem (e.g.
        # opentelemetry-exporter-otlp). Google::Protobuf::DescriptorPool is a single
        # process-wide global, and registering the same proto file into it twice raises
        # (`duplicate file name`). Since we deliberately require our own copies via
        # require_relative (so our behavior doesn't depend on gem load order), we may
        # attempt to register a file that some other gem already registered first. Guard
        # every registration through here instead of calling add_serialized_file directly.
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
