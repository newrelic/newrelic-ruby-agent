# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# Exercises ProfileEncoder against the real `google-protobuf` gem, hence the multiverse
# suite rather than the main unit suite (which doesn't have that gem installed).
# ProfileEncoder is never required unconditionally by the main agent load path, so it must
# be required explicitly here.
require 'new_relic/agent/continuous_profiling/profile_encoder'

OTelCollector = Opentelemetry::Proto::Collector::Profiles::V1development

class ProfileEncoderTest < Minitest::Test
  # Two occurrences of stack [main, foo, bar] (leaf=bar), one of [main, foo, baz].
  # StackProf's :raw/:raw_lines store each stack root-first: [length, frame_ids..., weight].
  REPORT = {
    version: 1.2,
    mode: :cpu,
    interval: 1000,
    samples: 3,
    gc_samples: 0,
    missed_samples: 0,
    frames: {
      1 => {name: 'Object#main', file: '/app/main.rb', line: 1, total_samples: 3, samples: 0},
      2 => {name: 'Object#foo', file: '/app/foo.rb', line: 5, total_samples: 3, samples: 0},
      3 => {name: 'Object#bar', file: '/app/bar.rb', line: 10, total_samples: 2, samples: 2},
      4 => {name: 'Object#baz', file: '/app/baz.rb', line: 20, total_samples: 1, samples: 1}
    },
    raw: [3, 1, 2, 3, 2, 3, 1, 2, 4, 1],
    raw_lines: [3, 1, 5, 10, 2, 3, 1, 5, 20, 1]
  }.freeze

  def setup
    @bytes = NewRelic::Agent::ContinuousProfiling::ProfileEncoder.encode(REPORT)
    @decoded = OTelCollector::ExportProfilesServiceRequest.decode(@bytes)
    @dict = @decoded.dictionary
    @profile = @decoded.resource_profiles[0].scope_profiles[0].profiles[0]
  end

  def test_encodes_a_decodable_export_profiles_service_request
    assert_kind_of OTelCollector::ExportProfilesServiceRequest, @decoded
  end

  def test_dedupes_shared_frames_into_the_function_table
    names = @dict.function_table.map { |f| @dict.string_table[f.name_strindex] }

    assert_equal ['', 'Object#main', 'Object#foo', 'Object#bar', 'Object#baz'], names
  end

  def test_aggregates_repeated_identical_stacks_into_one_sample
    assert_equal 2, @profile.samples.length
  end

  def test_stacks_are_ordered_leaf_first
    bar_sample = @profile.samples.find { |s| sample_leaf_name(s) == 'Object#bar' }
    names = stack_names(bar_sample)

    assert_equal %w[Object#bar Object#foo Object#main], names
  end

  def test_sample_values_carry_the_stackprof_weight_as_nanoseconds
    bar_sample = @profile.samples.find { |s| sample_leaf_name(s) == 'Object#bar' }
    baz_sample = @profile.samples.find { |s| sample_leaf_name(s) == 'Object#baz' }

    assert_equal [2_000_000], bar_sample.values.to_a
    assert_equal [1_000_000], baz_sample.values.to_a
  end

  def test_sample_type_reflects_mode_and_a_nanoseconds_unit
    assert_equal 'cpu', @dict.string_table[@profile.sample_type.type_strindex]
    assert_equal 'nanoseconds', @dict.string_table[@profile.sample_type.unit_strindex]
  end

  def test_period_reflects_the_stackprof_interval_in_nanoseconds
    assert_equal 1_000_000, @profile.period
  end

  def test_defaults_time_unix_nano_and_duration_nano_to_zero_without_a_window
    assert_equal 0, @profile.time_unix_nano
    assert_equal 0, @profile.duration_nano
  end

  def test_time_unix_nano_and_duration_nano_reflect_the_sampling_window
    report = REPORT.merge(window_start_realtime: 1_700_000_000.5, window_duration_nanos: 10_000_000_000)
    profile = profile_from(encode_and_decode(report))

    assert_equal 1_700_000_000_500_000_000, profile.time_unix_nano
    assert_equal 10_000_000_000, profile.duration_nano
  end

  def test_profile_id_and_instrumentation_scope_are_populated
    scope = @decoded.resource_profiles[0].scope_profiles[0].scope

    assert_equal 16, @profile.profile_id.bytesize
    assert_equal 'newrelic-ruby-agent', scope.name
    assert_equal NewRelic::VERSION::STRING, scope.version
  end

  OBJECT_REPORT = {
    mode: :object,
    interval: 1,
    frames: {
      1 => {name: 'Object#main', file: '/app/main.rb', line: 1},
      2 => {name: 'Object#foo', file: '/app/foo.rb', line: 5}
    },
    raw: [2, 1, 2, 3],
    raw_lines: [2, 1, 5, 3]
  }.freeze

  def test_object_mode_sample_type_reflects_mode_and_a_count_unit
    decoded = encode_and_decode(OBJECT_REPORT)
    dict = decoded.dictionary
    profile = profile_from(decoded)

    assert_equal 'object', dict.string_table[profile.sample_type.type_strindex]
    assert_equal 'count', dict.string_table[profile.sample_type.unit_strindex]
  end

  def test_object_mode_period_reflects_the_raw_allocation_interval
    profile = profile_from(encode_and_decode(OBJECT_REPORT))

    assert_equal 1, profile.period
  end

  def test_object_mode_sample_values_carry_the_raw_allocation_count_unconverted
    profile = profile_from(encode_and_decode(OBJECT_REPORT))

    assert_equal [3], profile.samples[0].values.to_a
  end

  def test_resource_carries_the_configured_app_name
    with_config(:app_name => %w[MyApp]) do
      decoded = encode_and_decode(REPORT)

      assert_equal 'MyApp', decoded.resource_profiles[0].resource.attributes[0].value.string_value
    end
  end

  def test_resource_carries_the_entity_guid_when_present
    with_config(:entity_guid => 'abc123') do
      decoded = encode_and_decode(REPORT)
      attributes = decoded.resource_profiles[0].resource.attributes

      entity_guid_attribute = attributes.find { |attr| attr.key == 'entity.guid' }

      refute_nil entity_guid_attribute
      assert_equal 'abc123', entity_guid_attribute.value.string_value
    end
  end

  def test_resource_omits_entity_guid_when_not_present
    with_config(:entity_guid => nil) do
      decoded = encode_and_decode(REPORT)
      attributes = decoded.resource_profiles[0].resource.attributes

      assert_nil attributes.find { |attr| attr.key == 'entity.guid' }
    end
  end

  def test_handles_an_empty_report_without_raising
    decoded = encode_and_decode(mode: :cpu, interval: 1000, raw: [], raw_lines: [])

    assert_empty profile_from(decoded).samples
  end

  def test_without_segment_ranges_only_the_link_placeholder_exists
    # REPORT carries no :segment_ranges/:clock_offset keys, as when Session hasn't
    # populated them yet or nothing was seen during the harvest.
    assert_equal 1, @dict.link_table.length
    assert(@profile.samples.all? { |s| s.link_index.zero? })
  end

  def test_placeholder_index_zero_exists_in_every_dictionary_table
    profiles_module = Opentelemetry::Proto::Profiles::V1development

    assert_equal profiles_module::Mapping.new, @dict.mapping_table[0]
    assert_equal profiles_module::Location.new, @dict.location_table[0]
    assert_equal profiles_module::Stack.new, @dict.stack_table[0]
    assert_operator @dict.location_table.length, :>, 1
    assert_operator @dict.stack_table.length, :>, 1
    refute_includes @dict.location_table[1..], profiles_module::Location.new
    refute_includes @dict.stack_table[1..], profiles_module::Stack.new
  end

  def test_links_a_sample_to_the_single_matching_segment_range
    report = REPORT.merge(
      raw_sample_timestamps: [1_000_000, 1_000_000, 2_000_000],
      clock_offset: 0.0,
      segment_ranges: [['a' * 32, 'b' * 16, 0.5, 1.5]]
    )

    decoded = encode_and_decode(report)
    dict = decoded.dictionary
    profile = profile_from(decoded)
    bar_sample = profile.samples.find { |s| sample_leaf_name(s, dict) == 'Object#bar' }
    link = dict.link_table[bar_sample.link_index]

    refute_equal 0, bar_sample.link_index
    assert_equal 'a' * 32, link.trace_id.unpack1('H*')
    assert_equal 'b' * 16, link.span_id.unpack1('H*')
  end

  def test_leaves_a_tick_unlinked_when_ranges_from_different_transactions_overlap_it
    report = REPORT.merge(
      raw_sample_timestamps: [1_000_000, 1_000_000, 2_000_000],
      clock_offset: 0.0,
      segment_ranges: [
        ['a' * 32, 'b' * 16, 0.5, 1.5],
        ['c' * 32, 'd' * 16, 0.8, 1.2],
        # Positive control: unambiguous, so correlation isn't just wholly broken.
        ['e' * 32, 'f' * 16, 1.8, 2.2]
      ]
    )

    decoded = encode_and_decode(report)
    dict = decoded.dictionary
    profile = profile_from(decoded)
    bar_sample = profile.samples.find { |s| sample_leaf_name(s, dict) == 'Object#bar' }
    baz_sample = profile.samples.find { |s| sample_leaf_name(s, dict) == 'Object#baz' }

    assert_equal 0, bar_sample.link_index
    refute_equal 0, baz_sample.link_index
    assert_equal 'f' * 16, dict.link_table[baz_sample.link_index].span_id.unpack1('H*')
  end

  def test_prefers_the_narrowest_matching_range_within_the_same_transaction
    # Root spans the whole window; child only covers the bar-leaf ticks. Same trace_id, so
    # the child should win where it applies; the baz-leaf tick falls back to the root.
    report = REPORT.merge(
      raw_sample_timestamps: [1_000_000, 1_000_000, 2_000_000],
      clock_offset: 0.0,
      segment_ranges: [
        ['a' * 32, 'b' * 16, 0.0, 3.0],
        ['a' * 32, 'e' * 16, 0.8, 1.2]
      ]
    )

    decoded = encode_and_decode(report)
    dict = decoded.dictionary
    profile = profile_from(decoded)
    bar_sample = profile.samples.find { |s| sample_leaf_name(s, dict) == 'Object#bar' }
    baz_sample = profile.samples.find { |s| sample_leaf_name(s, dict) == 'Object#baz' }

    assert_equal 'e' * 16, dict.link_table[bar_sample.link_index].span_id.unpack1('H*')
    assert_equal 'b' * 16, dict.link_table[baz_sample.link_index].span_id.unpack1('H*')
    refute_equal 0, baz_sample.link_index
    assert_equal [2_000_000], bar_sample.values.to_a
  end

  def test_splits_a_stackprof_collapsed_run_when_ticks_match_different_transactions
    # raw: [1, 1, 2] is a single collapsed group (weight 2) whose two ticks land in different
    # segment_ranges below.
    report = {
      mode: :cpu, interval: 1000,
      frames: {1 => {name: 'Object#main', file: '/app/main.rb', line: 1}},
      raw: [1, 1, 2],
      raw_lines: [1, 1, 2],
      raw_sample_timestamps: [1_000_000, 5_000_000],
      clock_offset: 0.0,
      segment_ranges: [
        ['a' * 32, 'b' * 16, 0.5, 2.0],
        ['c' * 32, 'd' * 16, 4.5, 6.0]
      ]
    }

    decoded = encode_and_decode(report)
    dict = decoded.dictionary
    profile = profile_from(decoded)

    assert_equal 2, profile.samples.length
    assert(profile.samples.all? { |s| s.values.to_a == [1_000_000] })
    trace_ids = profile.samples.map { |s| dict.link_table[s.link_index].trace_id.unpack1('H*') }

    assert_equal ['a' * 32, 'c' * 32], trace_ids.sort
  end

  def test_sorts_out_of_order_segment_ranges_by_start_time_before_matching
    # Session appends ranges in finish order, not start order -- out of order here on purpose.
    report = {
      mode: :cpu, interval: 1000,
      frames: {1 => {name: 'Object#main', file: '/app/main.rb', line: 1}},
      raw: [1, 1, 1],
      raw_lines: [1, 1, 1],
      raw_sample_timestamps: [1_000_000],
      clock_offset: 0.0,
      segment_ranges: [
        ['f' * 32, 'c' * 16, 2.5, 3.0],
        ['f' * 32, 'b' * 16, 0.0, 4.0]
      ]
    }

    decoded = encode_and_decode(report)
    dict = decoded.dictionary
    sample = profile_from(decoded).samples[0]

    refute_equal 0, sample.link_index
    assert_equal 'b' * 16, dict.link_table[sample.link_index].span_id.unpack1('H*')
  end

  def test_dedupes_two_distinct_stacks_linked_to_the_same_trace_and_span
    report = {
      mode: :cpu, interval: 1000,
      frames: {
        1 => {name: 'Object#main', file: '/app/main.rb', line: 1},
        2 => {name: 'Object#other', file: '/app/other.rb', line: 1}
      },
      raw: [1, 1, 1, 1, 2, 1],
      raw_lines: [1, 1, 1, 1, 1, 1],
      raw_sample_timestamps: [1_000_000, 2_000_000],
      clock_offset: 0.0,
      segment_ranges: [['a' * 32, 'b' * 16, 0.0, 5.0]]
    }

    decoded = encode_and_decode(report)
    dict = decoded.dictionary
    profile = profile_from(decoded)

    assert_equal 2, profile.samples.length
    link_indices = profile.samples.map(&:link_index).uniq

    assert_equal 1, link_indices.length
    refute_equal 0, link_indices.first
    assert_equal 2, dict.link_table.length
  end

  def test_build_tick_links_handles_timestamps_with_no_segment_ranges
    report = {
      mode: :cpu, interval: 1000,
      frames: {1 => {name: 'Object#main', file: '/app/main.rb', line: 1}},
      raw: [1, 1, 1],
      raw_lines: [1, 1, 1],
      raw_sample_timestamps: [1_000_000],
      clock_offset: 0.0,
      segment_ranges: []
    }

    decoded = encode_and_decode(report)

    assert_equal 0, profile_from(decoded).samples[0].link_index
  end

  def test_build_tick_links_handles_a_nil_clock_offset
    report = {
      mode: :cpu, interval: 1000,
      frames: {1 => {name: 'Object#main', file: '/app/main.rb', line: 1}},
      raw: [1, 1, 1],
      raw_lines: [1, 1, 1],
      raw_sample_timestamps: [1_000_000],
      clock_offset: nil,
      segment_ranges: [['a' * 32, 'b' * 16, 0.0, 5.0]]
    }

    decoded = encode_and_decode(report)

    assert_equal 0, profile_from(decoded).samples[0].link_index
  end

  def test_log_correlation_summary_reflects_the_actual_link_table
    report = REPORT.merge(
      raw_sample_timestamps: [1_000_000, 1_000_000, 2_000_000],
      clock_offset: 0.0,
      segment_ranges: [
        ['a' * 32, 'b' * 16, 0.5, 1.5],
        ['c' * 32, 'd' * 16, 1.8, 2.2]
      ]
    )

    log = with_array_logger(:debug) do
      NewRelic::Agent::ContinuousProfiling::ProfileEncoder.encode(report)
    end

    assert_log_contains(log, /correlated samples to 2 distinct span\(s\) across 2 distinct trace\(s\)/)
  end

  def encode_and_decode(report)
    bytes = NewRelic::Agent::ContinuousProfiling::ProfileEncoder.encode(report)
    OTelCollector::ExportProfilesServiceRequest.decode(bytes)
  end

  def profile_from(decoded)
    decoded.resource_profiles[0].scope_profiles[0].profiles[0]
  end

  def stack_index_for(sample)
    sample.stack_index
  end

  def sample_leaf_name(sample, dict = @dict)
    stack_names(sample, dict).first
  end

  def stack_names(sample, dict = @dict)
    dict.stack_table[sample.stack_index].location_indices.map do |location_index|
      location = dict.location_table[location_index]
      function = dict.function_table[location.lines[0].function_index]
      dict.string_table[function.name_strindex]
    end
  end
end
