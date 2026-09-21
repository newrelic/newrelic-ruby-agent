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

          # v1development is unstable, so a revision another gem registered first may resolve
          # without the fields ProfileEncoder sets. An empty list means the message is constructed
          # with no fields, so only its existence matters.
          REQUIRED_FIELDS = {
            'opentelemetry.proto.profiles.v1development.ProfilesDictionary' =>
              %w[mapping_table location_table function_table link_table string_table attribute_table stack_table],
            'opentelemetry.proto.profiles.v1development.ResourceProfiles' => %w[resource scope_profiles],
            'opentelemetry.proto.profiles.v1development.ScopeProfiles' => %w[scope profiles],
            'opentelemetry.proto.profiles.v1development.Profile' =>
              %w[sample_type samples time_unix_nano duration_nano period_type period profile_id],
            'opentelemetry.proto.profiles.v1development.Sample' => %w[stack_index link_index values],
            'opentelemetry.proto.profiles.v1development.Stack' => %w[location_indices],
            'opentelemetry.proto.profiles.v1development.Location' => %w[lines],
            'opentelemetry.proto.profiles.v1development.Line' => %w[function_index line],
            'opentelemetry.proto.profiles.v1development.Function' => %w[name_strindex filename_strindex start_line],
            'opentelemetry.proto.profiles.v1development.ValueType' => %w[type_strindex unit_strindex],
            'opentelemetry.proto.profiles.v1development.Link' => %w[trace_id span_id],
            'opentelemetry.proto.profiles.v1development.Mapping' => [],
            'opentelemetry.proto.profiles.v1development.KeyValueAndUnit' => [],
            'opentelemetry.proto.collector.profiles.v1development.ExportProfilesServiceRequest' =>
              %w[resource_profiles dictionary]
          }.freeze

          def self.incompatible_messages(pool = ::Google::Protobuf::DescriptorPool.generated_pool)
            REQUIRED_FIELDS.each_with_object([]) do |(message_name, fields), incompatible|
              descriptor = pool.lookup(message_name)

              unless descriptor
                incompatible << "#{message_name} is not registered"
                next
              end

              missing = fields.reject { |field| descriptor.lookup(field) }
              incompatible << "#{message_name} is missing #{missing.join(', ')}" unless missing.empty?
            end
          end

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
