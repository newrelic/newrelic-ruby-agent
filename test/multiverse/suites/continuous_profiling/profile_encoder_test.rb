# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# Exercises ProfileEncoder against the real `google-protobuf` gem, hence the multiverse
# suite rather than the main unit suite (which doesn't have that gem installed).
# ProfileEncoder is never required unconditionally by the main agent load path, so it must
# be required explicitly here.
require 'new_relic/agent/continuous_profiling/profile_encoder'

OTelCollector = Opentelemetry::Proto::Collector::Profiles::V1development
OTelProfiles = Opentelemetry::Proto::Profiles::V1development

class ProfileEncoderTest < Minitest::Test
  # Two occurrences of stack [main, foo, bar] (leaf=bar), one of [main, foo, baz].
  # StackProf's :raw/:raw_lines store each stack root-first: [length, frame_ids..., weight].
  REPORT = {
    version: 1.2,
    mode: :wall,
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

  def test_sample_values_carry_the_stackprof_weight
    bar_sample = @profile.samples.find { |s| sample_leaf_name(s) == 'Object#bar' }
    baz_sample = @profile.samples.find { |s| sample_leaf_name(s) == 'Object#baz' }

    assert_equal [2], bar_sample.values.to_a
    assert_equal [1], baz_sample.values.to_a
  end

  def test_sample_type_reflects_mode_and_a_count_unit
    assert_equal 'wall', @dict.string_table[@profile.sample_type.type_strindex]
    assert_equal 'count', @dict.string_table[@profile.sample_type.unit_strindex]
  end

  def test_period_reflects_the_stackprof_interval
    assert_equal 1000, @profile.period
  end

  def test_resource_carries_the_configured_app_name
    with_config(:app_name => %w[MyApp]) do
      bytes = NewRelic::Agent::ContinuousProfiling::ProfileEncoder.encode(REPORT)
      decoded = OTelCollector::ExportProfilesServiceRequest.decode(bytes)

      assert_equal 'MyApp', decoded.resource_profiles[0].resource.attributes[0].value.string_value
    end
  end

  def test_handles_an_empty_report_without_raising
    bytes = NewRelic::Agent::ContinuousProfiling::ProfileEncoder.encode(mode: :wall, interval: 1000, raw: [], raw_lines: [])
    decoded = OTelCollector::ExportProfilesServiceRequest.decode(bytes)

    assert_empty decoded.resource_profiles[0].scope_profiles[0].profiles[0].samples
  end

  def sample_leaf_name(sample)
    stack_names(sample).first
  end

  def stack_names(sample)
    @dict.stack_table[sample.stack_index].location_indices.map do |location_index|
      location = @dict.location_table[location_index]
      function = @dict.function_table[location.lines[0].function_index]
      @dict.string_table[function.name_strindex]
    end
  end
end
