# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# Exercises Session/StackProfSampler against the real `stackprof` gem. Unit tests for these
# classes stub StackProf entirely, so this suite is what actually proves the
# StackProf.start/stop/results round-trip works as expected.

class ContinuousProfilingTest < Minitest::Test
  def test_stack_prof_sampler_round_trips_against_the_real_gem
    sampler = NewRelic::Agent::ContinuousProfiling::StackProfSampler.new

    with_config(:'profiling.mode' => 'cpu', :'profiling.sample_period' => 0.001) do
      sampler.start
      busy_wait(0.1)
      report = sampler.stop_and_collect

      assert_operator report[:samples], :>, 0
      assert_equal :cpu, report[:mode]
      refute_empty report[:raw_sample_timestamps]
      assert_in_delta report[:window_start_realtime],
        report[:clock_offset] + report[:raw_sample_timestamps].first / 1_000_000.0, 0.5
    end
  end

  def test_stack_prof_sampler_round_trips_in_object_mode_against_the_real_gem
    sampler = NewRelic::Agent::ContinuousProfiling::StackProfSampler.new

    with_config(:'profiling.mode' => 'object', :'profiling.object_allocation_interval' => 1000) do
      sampler.start
      allocate_objects(5000)
      report = sampler.stop_and_collect

      assert_operator report[:samples], :>, 0
      assert_equal :object, report[:mode]
    end
  end

  def test_session_runs_a_full_harvest_cycle_against_the_real_gem
    with_config(:'profiling.mode' => 'cpu',
      :'profiling.sample_period' => 0.001,
      :'profiling.harvest_period' => 1) do
      session = NewRelic::Agent::ContinuousProfiling::Session.new(nil)

      log = with_array_logger(:debug) do
        session.start
        busy_wait(1.5)
        session.stop
      end

      refute_predicate session, :running?
      assert_nil session.instance_variable_get(:@thread)
      assert_metrics_recorded('Supportability/Ruby/Profiling/Disabled')
      assert_log_contains(log, /Continuous profiling collected [1-9]\d* sample/)
      refute_log_contains(log, /Error harvesting/)
    end
  end

  # Runs real sampling and real protobuf encoding end to end, stubbing only the final
  # socket hop -- what's at risk is whether a real StackProf report survives real
  # protobuf encoding intact, not Net::HTTP itself.
  def test_full_pipeline_produces_a_decodable_export_profiles_service_request
    require 'new_relic/agent/continuous_profiling/profile_encoder'

    connection = stub_everything('http connection')
    request = nil
    response = stub_everything('response', :code => '202', :message => 'Accepted', :body => '')
    connection.stubs(:request).with { |req| request = req; true }.returns(response)
    Net::HTTP.stubs(:new).returns(connection)

    server = NewRelic::Control::Server.new('somewhere.example.com', 30303)
    service = NewRelic::Agent::NewRelicService.new('license-key', server)
    service.agent_id = 666

    with_config(:'profiling.mode' => 'cpu',
      :'profiling.sample_period' => 0.001) do
      sampler = NewRelic::Agent::ContinuousProfiling::StackProfSampler.new
      sampler.start
      busy_wait(0.1)
      report = sampler.stop_and_collect

      bytes = NewRelic::Agent::ContinuousProfiling::ProfileEncoder.encode(report)
      service.profiles_data(bytes)
    end

    refute_nil request
    decoded = Opentelemetry::Proto::Collector::Profiles::V1development::ExportProfilesServiceRequest.decode(request.body)

    refute_empty decoded.resource_profiles[0].scope_profiles[0].profiles[0].samples
  end

  def test_full_pipeline_writes_a_human_readable_body_to_the_audit_log
    require 'new_relic/agent/continuous_profiling/profile_encoder'

    connection = stub_everything('http connection')
    response = stub_everything('response', :code => '202', :message => 'Accepted', :body => '')
    connection.stubs(:request).returns(response)
    Net::HTTP.stubs(:new).returns(connection)

    output = with_config(:'profiling.mode' => 'cpu',
      :'profiling.sample_period' => 0.001,
      :'audit_log.enabled' => true,
      :'audit_log.path' => 'STDOUT') do
      capturing_stdout do
        server = NewRelic::Control::Server.new('somewhere.example.com', 30303)
        service = NewRelic::Agent::NewRelicService.new('license-key', server)
        service.agent_id = 666

        sampler = NewRelic::Agent::ContinuousProfiling::StackProfSampler.new
        sampler.start
        busy_wait(0.1)
        report = sampler.stop_and_collect

        bytes = NewRelic::Agent::ContinuousProfiling::ProfileEncoder.encode(report)
        service.profiles_data(bytes)
      end
    end

    assert_includes output, 'REQUEST BODY:'
    assert_includes output, 'resource_profiles'
    assert_includes output, 'license-ke*'
    refute_includes output, 'license-key'
  end

  # Feeds a real Session's segment_ranges into the real ProfileEncoder, unlike every other
  # correlation test's hand-built array literals -- catches a tuple reorder those would miss.
  def test_segment_ranges_recorded_by_a_real_session_correlate_correctly_through_the_encoder
    require 'new_relic/agent/continuous_profiling/profile_encoder'

    session = NewRelic::Agent::ContinuousProfiling::Session.new(NewRelic::Agent.agent.events)
    session.instance_variable_set(:@running, true)
    # Matches what start() would have set -- otherwise restart_if_forked sees @starting_pid
    # (nil) != Process.pid and treats this as a fork, resetting state and spawning a real
    # background StackProf session that this test never stops.
    session.instance_variable_set(:@starting_pid, Process.pid)
    session.send(:subscribe_to_transaction_hooks)

    in_transaction('profiled_txn') do |txn|
      txn.trace_id # force generation, as real distributed-tracing code paths do
      sleep(0.02)
    end

    segment_ranges = session.send(:drain_segment_ranges)
    session.send(:unsubscribe_from_transaction_hooks)

    refute_empty segment_ranges
    trace_id, span_id, start_time, end_time = segment_ranges.first

    # clock_offset: 0.0 makes "monotonic" ticks equal to wall-clock seconds, so the real
    # segment's own wall-clock midpoint can be used directly as the tick's timestamp.
    tick_timestamp_usec = ((start_time + end_time) / 2 * 1_000_000).to_i
    report = {
      mode: :cpu, interval: 1000,
      frames: {1 => {name: 'Object#work', file: '/app/work.rb', line: 1}},
      raw: [1, 1, 1],
      raw_lines: [1, 1, 1],
      raw_sample_timestamps: [tick_timestamp_usec],
      clock_offset: 0.0,
      segment_ranges: segment_ranges
    }

    bytes = NewRelic::Agent::ContinuousProfiling::ProfileEncoder.encode(report)
    decoded = Opentelemetry::Proto::Collector::Profiles::V1development::ExportProfilesServiceRequest.decode(bytes)
    dict = decoded.dictionary
    sample = decoded.resource_profiles[0].scope_profiles[0].profiles[0].samples[0]

    refute_equal 0, sample.link_index
    assert_equal trace_id, dict.link_table[sample.link_index].trace_id.unpack1('H*')
    assert_equal span_id, dict.link_table[sample.link_index].span_id.unpack1('H*')
  end

  def capturing_stdout
    orig = $stdout.dup
    output = +''
    $stdout = StringIO.new(output)
    yield
    output
  ensure
    $stdout = orig
  end

  def busy_wait(seconds)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    x = 0
    x += 1 while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
  end

  def allocate_objects(count)
    count.times { Object.new }
  end
end
