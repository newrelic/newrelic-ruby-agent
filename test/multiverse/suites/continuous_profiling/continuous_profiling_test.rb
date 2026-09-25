# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# The unit suite stubs StackProf entirely; this suite is what proves the round-trip works.

require 'timeout'

class ContinuousProfilingTest < Minitest::Test
  # Resolved at call time, not as a constant: the tests below require the encoder individually,
  # and the generated proto classes don't exist until one of them has.
  def export_request
    NewRelic::Agent::ContinuousProfiling::Proto::ExportProfilesServiceRequest
  end

  def test_stack_prof_sampler_round_trips_against_the_real_gem
    sampler = NewRelic::Agent::ContinuousProfiling::StackProfSampler.new

    with_config(:'profiling.include' => 'cpu', :'profiling.sample_period' => 0.001) do
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

    with_config(:'profiling.include' => 'object', :'profiling.object_allocation_interval' => 1000) do
      sampler.start
      allocate_objects(5000)
      report = sampler.stop_and_collect

      assert_operator report[:samples], :>, 0
      assert_equal :object, report[:mode]
    end
  end

  def test_session_runs_a_full_harvest_cycle_against_the_real_gem
    with_config(:'profiling.include' => 'cpu',
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

  def test_session_stops_stackprof_and_stays_restartable_once_the_duration_elapses
    with_config(:'profiling.include' => 'cpu',
      :'profiling.sample_period' => 0.001,
      :'profiling.harvest_period' => 1,
      :'profiling.duration' => 200) do
      session = NewRelic::Agent::ContinuousProfiling::Session.new(nil)

      session.start
      session.instance_variable_get(:@thread).join(5)

      refute_predicate session, :running?
      refute_predicate StackProf, :running?, 'Expected StackProf to be stopped once the duration elapsed'
      assert_metrics_recorded('Supportability/Ruby/Profiling/Duration')

      session.start

      assert_predicate session, :running?
      assert_predicate StackProf, :running?, 'Expected a duration-ended session to be restartable'
      session.stop
    end
  ensure
    StackProf.stop if StackProf.running?
  end

  def test_session_stops_stackprof_when_a_stop_lands_during_an_export
    with_config(:'profiling.include' => 'cpu',
      :'profiling.sample_period' => 0.001,
      :'profiling.harvest_period' => 1) do
      session = NewRelic::Agent::ContinuousProfiling::Session.new(nil)
      exporting = Queue.new
      release = Queue.new
      session.define_singleton_method(:encode_and_export) do |_report|
        exporting.push(:exporting)
        release.pop
      end

      session.start
      Timeout.timeout(10) { exporting.pop }

      assert_predicate StackProf, :running?, 'Expected sampling to be restarted ahead of the export'

      stopper = Thread.new { session.stop }
      Timeout.timeout(10) { Thread.pass while session.running? }
      release.push(:release)
      stopper.join(10)

      refute_predicate StackProf, :running?, 'Expected StackProf to be stopped after a stop mid-export'
      assert_nil session.instance_variable_get(:@thread)
    end
  ensure
    StackProf.stop if StackProf.running?
  end

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

    with_config(:'profiling.include' => 'cpu',
      :'profiling.sample_period' => 0.001) do
      sampler = NewRelic::Agent::ContinuousProfiling::StackProfSampler.new
      sampler.start
      busy_wait(0.1)
      report = sampler.stop_and_collect

      bytes = NewRelic::Agent::ContinuousProfiling::ProfileEncoder.encode(report)
      service.profiles_data(bytes)
    end

    refute_nil request
    decoded = export_request.decode(request.body)

    refute_empty decoded.resource_profiles[0].scope_profiles[0].profiles[0].samples
  end

  def test_full_pipeline_writes_a_human_readable_body_to_the_audit_log
    require 'new_relic/agent/continuous_profiling/profile_encoder'

    connection = stub_everything('http connection')
    response = stub_everything('response', :code => '202', :message => 'Accepted', :body => '')
    connection.stubs(:request).returns(response)
    Net::HTTP.stubs(:new).returns(connection)

    output = with_config(:'profiling.include' => 'cpu',
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

  # The only correlation test not built on hand-written tuples, so a tuple reorder can't slip by.
  def test_segment_ranges_recorded_by_a_real_session_correlate_correctly_through_the_encoder
    require 'new_relic/agent/continuous_profiling/profile_encoder'

    session = NewRelic::Agent::ContinuousProfiling::Session.new(NewRelic::Agent.agent.events)
    session.instance_variable_set(:@running, true)
    # Without this, restart_if_forked reads @starting_pid as nil, treats the test as a fork, and
    # spawns a real background StackProf session that nothing ever stops.
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
    decoded = export_request.decode(bytes)
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
