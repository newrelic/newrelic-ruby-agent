# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'securerandom'
require_relative 'proto/opentelemetry/proto/collector/profiles/v1development/profiles_service_pb'

module NewRelic
  module Agent
    module ContinuousProfiling
      # Converts a StackProf.results report Hash into a serialized OTel Profiles signal
      # message (opentelemetry.proto.collector.profiles.v1development.ExportProfilesServiceRequest).
      #
      # StackProf's :raw/:raw_lines arrays are a flat encoding of repeated
      # [length, frame_id_1..frame_id_length, weight] (and the line-number equivalent)
      # groups, one per distinct stack observed, ordered root-first. OTel's Stack wants
      # location_indices ordered leaf-first, so each stack's frames are reversed on the way
      # in. Every table in the OTel ProfilesDictionary (functions, locations, stacks,
      # strings) is deduplicated within a single encode call -- dictionaries are scoped per
      # message, not persisted across harvests, so nothing here is cached between calls.
      #
      # Sample values are the StackProf-reported sample count for that stack (its "weight"),
      # not a time value -- pending confirmation of what the flame-graph UI actually expects
      # (see CONTINUOUS_PROFILING_PLAN.md's open items). Likewise, samples carry no
      # trace/span correlation and profile timestamps are approximate (wall-clock time at
      # encode time, not the actual sampling window) -- both explicitly deferred.
      class ProfileEncoder
        OTEL_PROFILES = Opentelemetry::Proto::Profiles::V1development
        OTEL_COLLECTOR = Opentelemetry::Proto::Collector::Profiles::V1development
        OTEL_COMMON = Opentelemetry::Proto::Common::V1
        OTEL_RESOURCE = Opentelemetry::Proto::Resource::V1

        SAMPLE_VALUE_UNIT = 'count'
        INSTRUMENTATION_SCOPE_NAME = 'newrelic-ruby-agent'

        def self.encode(report)
          new(report).encode
        end

        def initialize(report)
          @report = report
          @string_table = ['']
          @string_indices = {'' => 0}
          @function_table = [OTEL_PROFILES::Function.new]
          @function_indices = {}
          @location_table = [OTEL_PROFILES::Location.new]
          @location_indices = {}
          @stack_table = [OTEL_PROFILES::Stack.new]
          @stack_indices = {}
        end

        def encode
          OTEL_COLLECTOR::ExportProfilesServiceRequest.encode(request)
        end

        private

        def request
          OTEL_COLLECTOR::ExportProfilesServiceRequest.new(
            resource_profiles: [resource_profiles],
            dictionary: dictionary
          )
        end

        def resource_profiles
          OTEL_PROFILES::ResourceProfiles.new(
            resource: resource,
            scope_profiles: [scope_profiles]
          )
        end

        def resource
          OTEL_RESOURCE::Resource.new(attributes: [
            OTEL_COMMON::KeyValue.new(
              key: 'service.name',
              value: OTEL_COMMON::AnyValue.new(string_value: Array(NewRelic::Agent.config[:app_name]).first.to_s)
            )
          ])
        end

        def scope_profiles
          OTEL_PROFILES::ScopeProfiles.new(
            scope: OTEL_COMMON::InstrumentationScope.new(
              name: INSTRUMENTATION_SCOPE_NAME,
              version: NewRelic::VERSION::STRING
            ),
            profiles: [profile]
          )
        end

        def profile
          type = sample_type

          OTEL_PROFILES::Profile.new(
            sample_type: type,
            samples: samples,
            time_unix_nano: (Process.clock_gettime(Process::CLOCK_REALTIME) * 1_000_000_000).to_i,
            period_type: type,
            period: (@report[:interval] || 0).to_i,
            profile_id: SecureRandom.random_bytes(16)
          )
        end

        def sample_type
          OTEL_PROFILES::ValueType.new(
            type_strindex: intern(@report[:mode].to_s),
            unit_strindex: intern(SAMPLE_VALUE_UNIT)
          )
        end

        def samples
          frame_groups = parse_raw_groups(@report[:raw])
          line_groups = parse_raw_groups(@report[:raw_lines])

          frame_groups.each_with_index.map do |(frame_ids, weight), idx|
            lines = line_groups[idx]&.first || []
            location_ids = frame_ids.zip(lines).map { |frame_id, line| location_index(frame_id, line) }
            location_ids.reverse! # StackProf stores root-first; OTel Stacks want leaf-first

            OTEL_PROFILES::Sample.new(stack_index: stack_index(location_ids), values: [weight])
          end
        end

        # StackProf's :raw/:raw_lines are flat arrays of repeated
        # [length, item_1, .., item_length, weight] groups. Returns an array of
        # [items, weight] pairs.
        def parse_raw_groups(flat_array)
          groups = []
          i = 0
          array = flat_array || []

          while i < array.length
            length = array[i]
            items = array[i + 1, length]
            weight = array[i + 1 + length]
            groups << [items, weight]
            i += length + 2
          end

          groups
        end

        def function_index(frame_id)
          @function_indices[frame_id] ||= begin
            frame = @report[:frames][frame_id] || {}
            @function_table << OTEL_PROFILES::Function.new(
              name_strindex: intern(frame[:name].to_s),
              filename_strindex: intern(frame[:file].to_s),
              start_line: (frame[:line] || 0)
            )
            @function_table.length - 1
          end
        end

        def location_index(frame_id, line)
          key = [frame_id, line]
          @location_indices[key] ||= begin
            @location_table << OTEL_PROFILES::Location.new(
              lines: [OTEL_PROFILES::Line.new(function_index: function_index(frame_id), line: line || 0)]
            )
            @location_table.length - 1
          end
        end

        def stack_index(location_ids)
          key = location_ids.freeze
          @stack_indices[key] ||= begin
            @stack_table << OTEL_PROFILES::Stack.new(location_indices: key)
            @stack_table.length - 1
          end
        end

        def dictionary
          OTEL_PROFILES::ProfilesDictionary.new(
            mapping_table: [OTEL_PROFILES::Mapping.new],
            location_table: @location_table,
            function_table: @function_table,
            link_table: [OTEL_PROFILES::Link.new],
            string_table: @string_table,
            attribute_table: [OTEL_PROFILES::KeyValueAndUnit.new],
            stack_table: @stack_table
          )
        end

        def intern(string)
          @string_indices[string] ||= begin
            @string_table << string
            @string_table.length - 1
          end
        end
      end
    end
  end
end
