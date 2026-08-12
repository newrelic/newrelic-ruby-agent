# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'securerandom'
require_relative 'proto/opentelemetry/proto/collector/profiles/v1development/profiles_service_pb'

module NewRelic
  module Agent
    module ContinuousProfiling
      # Converts a StackProf.results report Hash (as produced by StackProfSampler) into a
      # serialized opentelemetry.proto.collector.profiles.v1development.ExportProfilesServiceRequest.
      # ProfilesDictionary tables are deduped per encode call only -- nothing persists across
      # harvests.
      class ProfileEncoder
        OTEL_PROFILES = Opentelemetry::Proto::Profiles::V1development
        OTEL_COLLECTOR = Opentelemetry::Proto::Collector::Profiles::V1development
        OTEL_COMMON = Opentelemetry::Proto::Common::V1
        OTEL_RESOURCE = Opentelemetry::Proto::Resource::V1

        # :cpu samples carry a duration (StackProf tick count * interval), reported in
        # nanoseconds; :object samples carry a raw allocation count, which has no time unit.
        TIME_SAMPLE_VALUE_UNIT = 'nanoseconds'
        OBJECT_SAMPLE_VALUE_UNIT = 'count'
        NANOSECONDS_PER_MICROSECOND = 1_000
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
          @link_table = [OTEL_PROFILES::Link.new]
          @link_indices = {}
        end

        def encode
          req = request
          log_correlation_summary
          OTEL_COLLECTOR::ExportProfilesServiceRequest.encode(req)
        end

        private

        # link_table only fills in once `request` builds every Sample -- logged here after
        # that, since Session never sees these tables.
        def log_correlation_summary
          distinct_spans = @link_table.length - 1
          distinct_traces = @link_table[1..].map(&:trace_id).uniq.length
          NewRelic::Agent.logger.debug(
            "Continuous profiling correlated samples to #{distinct_spans} distinct span(s) across #{distinct_traces} distinct trace(s)"
          )
        end

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
            time_unix_nano: window_start_nanos,
            duration_nano: @report[:window_duration_nanos] || 0,
            period_type: type,
            period: period,
            profile_id: SecureRandom.random_bytes(16)
          )
        end

        def window_start_nanos
          ((@report[:window_start_realtime] || 0) * 1_000_000_000).to_i
        end

        def object_mode?
          @report[:mode] == :object
        end

        def sample_type
          OTEL_PROFILES::ValueType.new(
            type_strindex: intern(@report[:mode].to_s),
            unit_strindex: intern(object_mode? ? OBJECT_SAMPLE_VALUE_UNIT : TIME_SAMPLE_VALUE_UNIT)
          )
        end

        # :object mode's StackProf interval is already an allocation count, with no time
        # unit to convert; :cpu's is microseconds between ticks, converted to nanoseconds.
        def period
          object_mode? ? (@report[:interval] || 0) : tick_duration_nanos
        end

        def samples
          collapse_ticks(expand_ticks).map do |(location_ids, trace_id, span_id), weight|
            OTEL_PROFILES::Sample.new(
              stack_index: stack_index(location_ids),
              link_index: link_index(trace_id, span_id),
              values: [sample_value(weight)]
            )
          end
        end

        # :object mode's sample value is the raw allocation count (the StackProf tick
        # weight, unconverted); :cpu's is duration -- ticks * the per-tick interval.
        def sample_value(weight)
          object_mode? ? weight : weight * tick_duration_nanos
        end

        # Each StackProf tick represents one sample_period-length slice of time. Only
        # meaningful for time-based modes (:cpu) -- see sample_value/period for :object.
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
          tick_links = build_tick_links
          tick = 0
          ticks = []

          frame_groups.each_with_index do |(frame_ids, weight), idx|
            lines = line_groups[idx]&.first || []
            location_ids = frame_ids.zip(lines).map { |frame_id, line| location_index(frame_id, line) }
            location_ids.reverse! # StackProf stores root-first; OTel Stacks want leaf-first

            weight.times do
              ticks << [location_ids, *tick_links[tick]]
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

        # Sweeps ticks (already in chronological order) against ranges sorted by start_time,
        # instead of scanning every range per tick -- active-set size is bounded by real
        # concurrency, not total range count.
        def build_tick_links
          timestamps = @report[:raw_sample_timestamps]
          return [] if timestamps.nil? || timestamps.empty?

          ranges = @report[:segment_ranges]
          return Array.new(timestamps.length) { [nil, nil] } if ranges.nil? || ranges.empty?

          clock_offset = @report[:clock_offset]
          sorted = ranges.sort_by { |(_trace_id, _span_id, start_time, _end_time)| start_time }
          active = []
          idx = 0

          timestamps.map do |monotonic_usec|
            next [nil, nil] unless clock_offset

            timestamp = clock_offset + (monotonic_usec / 1_000_000.0)

            while idx < sorted.length && sorted[idx][2] <= timestamp
              active << sorted[idx]
              idx += 1
            end
            active.reject! { |(_trace_id, _span_id, _start_time, end_time)| end_time <= timestamp }

            link_for(active)
          end
        end

        # More than one trace_id among matches means concurrent transactions -- unknowable
        # from timestamp alone, so left unlinked. One trace_id picks the narrowest match.
        def link_for(matches)
          return [nil, nil] if matches.empty?

          trace_ids = matches.map { |(trace_id, *)| trace_id }.uniq
          return [nil, nil] if trace_ids.length > 1

          narrowest = matches.min_by { |(_trace_id, _span_id, start_time, end_time)| end_time - start_time }
          trace_id, span_id, = narrowest
          [trace_id, span_id]
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

        # Index 0 is the required all-zero placeholder Link, returned when build_tick_links
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

        def dictionary
          OTEL_PROFILES::ProfilesDictionary.new(
            mapping_table: [OTEL_PROFILES::Mapping.new],
            location_table: @location_table,
            function_table: @function_table,
            link_table: @link_table,
            string_table: @string_table,
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
