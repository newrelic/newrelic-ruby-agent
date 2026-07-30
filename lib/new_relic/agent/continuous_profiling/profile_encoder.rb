# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'securerandom'
require_relative 'proto/opentelemetry/proto/collector/profiles/v1development/profiles_service_pb'

module NewRelic
  module Agent
    module ContinuousProfiling
      # Converts a StackProf.results report Hash into a serialized
      # opentelemetry.proto.collector.profiles.v1development.ExportProfilesServiceRequest.
      #
      # StackProf's :raw/:raw_lines are flat, root-first-ordered stack encodings; OTel's
      # Stack wants location_indices leaf-first, so each stack is reversed on the way in.
      # The ProfilesDictionary tables are deduped per encode call only -- nothing persists
      # across harvests.
      #
      # Sample values are nanoseconds of CPU/wall time (StackProf's per-stack tick count times
      # the sample interval), matching the OTel profiles spec's ["cpu","nanoseconds"] convention
      # -- not a raw tick count. Timestamps are approximate (encode time, not the actual
      # sampling window) -- deferred, see CONTINUOUS_PROFILING_PLAN.md.
      #
      # Trace/span correlation is per-transaction, not truly per-sample -- see correlation_for.
      class ProfileEncoder
        OTEL_PROFILES = Opentelemetry::Proto::Profiles::V1development
        OTEL_COLLECTOR = Opentelemetry::Proto::Collector::Profiles::V1development
        OTEL_COMMON = Opentelemetry::Proto::Common::V1
        OTEL_RESOURCE = Opentelemetry::Proto::Resource::V1

        SAMPLE_VALUE_UNIT = 'nanoseconds'
        NANOSECONDS_PER_MICROSECOND = 1_000
        INSTRUMENTATION_SCOPE_NAME = 'newrelic-ruby-agent'
        ACTIVE_TRACE_IDS_ATTRIBUTE_KEY = 'correlation.active_trace_ids'

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
          @link_table = [OTEL_PROFILES::Link.new]
          @link_indices = {}
          @attribute_table = [OTEL_PROFILES::KeyValueAndUnit.new]
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
            period: tick_duration_nanos,
            profile_id: SecureRandom.random_bytes(16),
            attribute_indices: profile_attribute_indices
          )
        end

        def sample_type
          OTEL_PROFILES::ValueType.new(
            type_strindex: intern(@report[:mode].to_s),
            unit_strindex: intern(SAMPLE_VALUE_UNIT)
          )
        end

        def samples
          collapse_ticks(expand_ticks).map do |(location_ids, trace_id, span_id), weight|
            OTEL_PROFILES::Sample.new(
              stack_index: stack_index(location_ids),
              link_index: link_index(trace_id, span_id),
              values: [weight * tick_duration_nanos]
            )
          end
        end

        # Each StackProf tick represents one sample_period-length slice of time.
        def tick_duration_nanos
          (@report[:interval] || 0) * NANOSECONDS_PER_MICROSECOND
        end

        # StackProf's :raw/:raw_lines pre-collapse consecutive identical stacks into one
        # [frame_ids, weight] group, but :raw_sample_timestamps has one entry per tick. Expand
        # back to one entry per tick so each can be matched to a transaction individually,
        # then re-collapsed in collapse_ticks.
        def expand_ticks
          frame_groups = parse_raw_groups(@report[:raw])
          line_groups = parse_raw_groups(@report[:raw_lines])
          tick = 0
          ticks = []

          frame_groups.each_with_index do |(frame_ids, weight), idx|
            lines = line_groups[idx]&.first || []
            location_ids = frame_ids.zip(lines).map { |frame_id, line| location_index(frame_id, line) }
            location_ids.reverse! # StackProf stores root-first; OTel Stacks want leaf-first

            weight.times do
              ticks << [location_ids, *correlation_for(tick)]
              tick += 1
            end
          end

          ticks
        end

        # Re-collapses consecutive ticks with an identical [location_ids, trace_id, span_id],
        # mirroring StackProf's own consecutive-only collapsing -- splits stacks matched to
        # different transactions even if adjacent.
        def collapse_ticks(ticks)
          groups = []

          ticks.each do |tuple|
            if groups.any? && groups.last[0] == tuple
              groups.last[1] += 1
            else
              groups << [tuple, 1]
            end
          end

          groups
        end

        # tick_index is the tick's position in raw_sample_timestamps order. Returns
        # [trace_id, span_id] only when exactly one transaction range contains this tick's
        # wall-clock time; [nil, nil] otherwise (no match, or ambiguous under concurrency).
        def correlation_for(tick_index)
          ranges = @report[:transaction_ranges]
          return [nil, nil] if ranges.nil? || ranges.empty?

          timestamp = tick_realtime(tick_index)
          return [nil, nil] unless timestamp

          matches = ranges.select { |(_trace_id, _span_id, start_time, end_time)| timestamp >= start_time && timestamp < end_time }
          return [nil, nil] unless matches.length == 1

          trace_id, span_id, = matches.first
          [trace_id, span_id]
        end

        def tick_realtime(tick_index)
          monotonic_usec = @report[:raw_sample_timestamps]&.[](tick_index)
          clock_offset = @report[:clock_offset]
          return nil unless monotonic_usec && clock_offset

          clock_offset + (monotonic_usec / 1_000_000.0)
        end

        # StackProf's :raw/:raw_lines are flat [length, item_1, .., item_length, weight]
        # groups. Returns an array of [items, weight] pairs.
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

        # Index 0 is the required all-zero placeholder Link, returned when correlation_for
        # couldn't attribute a tick to exactly one transaction.
        def link_index(trace_id, span_id)
          return 0 unless trace_id && span_id

          key = [trace_id, span_id]
          @link_indices[key] ||= begin
            @link_table << OTEL_PROFILES::Link.new(trace_id: hex_to_bytes(trace_id), span_id: hex_to_bytes(span_id))
            @link_table.length - 1
          end
        end

        def hex_to_bytes(hex_string)
          [hex_string].pack('H*')
        end

        def profile_attribute_indices
          trace_ids = @report[:active_trace_ids]
          return [] if trace_ids.nil? || trace_ids.empty?

          [attribute_index(ACTIVE_TRACE_IDS_ATTRIBUTE_KEY, trace_ids)]
        end

        def attribute_index(key, string_values)
          @attribute_table << OTEL_PROFILES::KeyValueAndUnit.new(
            key_strindex: intern(key),
            value: OTEL_COMMON::AnyValue.new(
              array_value: OTEL_COMMON::ArrayValue.new(
                values: string_values.map { |value| OTEL_COMMON::AnyValue.new(string_value: value) }
              )
            )
          )
          @attribute_table.length - 1
        end

        def dictionary
          OTEL_PROFILES::ProfilesDictionary.new(
            mapping_table: [OTEL_PROFILES::Mapping.new],
            location_table: @location_table,
            function_table: @function_table,
            link_table: @link_table,
            string_table: @string_table,
            attribute_table: @attribute_table,
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
