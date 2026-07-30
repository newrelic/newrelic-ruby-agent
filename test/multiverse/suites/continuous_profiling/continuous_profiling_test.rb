# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# Exercises Session/StackProfSampler against the real `stackprof` gem. Unit tests for these
# classes stub StackProf entirely, so this suite is what actually proves the
# StackProf.start/stop/results round-trip works as expected.

class ContinuousProfilingTest < Minitest::Test
  def test_stack_prof_sampler_round_trips_against_the_real_gem
    sampler = NewRelic::Agent::ContinuousProfiling::StackProfSampler.new

    with_config(:'continuous_profiler.mode' => 'cpu', :'continuous_profiler.sample_period' => 0.001) do
      sampler.start
      busy_wait(0.1)
      report = sampler.stop_and_collect

      assert_operator report[:samples], :>, 0
      assert_equal :cpu, report[:mode]
    end
  end

  def test_session_runs_a_full_harvest_cycle_against_the_real_gem
    with_config(:'continuous_profiler.mode' => 'cpu',
      :'continuous_profiler.sample_period' => 0.001,
      :'continuous_profiler.harvest_period' => 1) do
      session = NewRelic::Agent::ContinuousProfiling::Session.new(nil)

      log = with_array_logger(:debug) do
        session.start
        busy_wait(1.5)
        session.stop
      end

      refute_predicate session, :running?
      assert_log_contains(log, /Continuous profiling collected \d+ sample/)
    end
  end

  # Runs real sampling and real protobuf encoding end to end, stubbing only the final
  # socket hop -- what's at risk is whether a real StackProf report survives real
  # protobuf encoding intact, not Net::HTTP itself.
  def test_full_pipeline_produces_a_decodable_export_profiles_service_request
    require 'new_relic/agent/continuous_profiling/profile_encoder'

    connection = stub_everything('http connection')
    request = nil
    connection.stubs(:request).with { |req| request = req; true }.returns(stub_everything('response'))
    Net::HTTP.stubs(:new).returns(connection)

    with_config(:'continuous_profiler.mode' => 'cpu',
      :'continuous_profiler.sample_period' => 0.001,
      :'continuous_profiler.otlp_endpoint.host' => 'otlp.example.com') do
      sampler = NewRelic::Agent::ContinuousProfiling::StackProfSampler.new
      sampler.start
      busy_wait(0.1)
      report = sampler.stop_and_collect

      bytes = NewRelic::Agent::ContinuousProfiling::ProfileEncoder.encode(report)
      NewRelic::Agent::ContinuousProfiling::OtlpExporter.new.export(bytes)
    end

    refute_nil request
    decompressed = Zlib.gunzip(request.body)
    decoded = Opentelemetry::Proto::Collector::Profiles::V1development::ExportProfilesServiceRequest.decode(decompressed)

    refute_empty decoded.resource_profiles[0].scope_profiles[0].profiles[0].samples
  end

  def busy_wait(seconds)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    x = 0
    x += 1 while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
  end
end
