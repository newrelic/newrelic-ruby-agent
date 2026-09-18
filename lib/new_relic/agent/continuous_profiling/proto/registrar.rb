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
          # Without serializing the lookup and the add, two threads requiring these files at
          # once both get past the lookup and the second add raises on the duplicate.
          LOCK = Mutex.new

          def self.register_once(pool, descriptor_data, anchor_message_name)
            LOCK.synchronize do
              if pool.lookup(anchor_message_name)
                NewRelic::Agent.logger.debug(
                  "Not registering #{anchor_message_name}: already present in the protobuf " \
                  'descriptor pool, registered by another gem'
                )
                return
              end

              pool.add_serialized_file(descriptor_data)
            end
          end
        end
      end
    end
  end
end
