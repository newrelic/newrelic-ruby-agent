# https://newrelic.atlassian.net/wiki/display/eng/Agent+Thread+Profiling
# https://newrelic.atlassian.net/browse/RUBY-917

if RUBY_VERSION >= '1.9'
class ThreadProfilingTest < Test::Unit::TestCase
  def setup
    NewRelic::Agent.manual_start(:'thread_profiler.enabled' => true)

    @agent = NewRelic::Agent.instance
    @thread_profiler = @agent.thread_profiler

    $collector ||= NewRelic::FakeCollector.new
    $collector.reset
    $collector.mock['connect'] = [200, '{"agent_run_id": 666 }']
    $collector.mock['get_agent_commands'] = [200, START_COMMAND]
    $collector.mock['agent_command_results'] = [200, '[]']
    $collector.run
  end

  def teardown
    $collector.reset
  end

  START_COMMAND = '[[666,{
      "name":"start_profiler",
      "arguments":{
        "profile_id":-1,
        "sample_period":0.01,
        "duration":0.5,
        "only_runnable_threads":false,
        "only_request_threads":false,
        "profile_agent_code":false
      }
    }]]'

  STOP_COMMAND = '[[666,{
      "name":"stop_profiler",
      "arguments":{
        "profile_id":-1,
        "report_data":true
      }
    }]]'

  # These are potentially fragile for being timing based
  # START_COMMAND with 0.01 sampling and 0.5 duration expects to get
  # roughly 50 polling cycles in. We check signficiantly less than that.

  # STOP_COMMAND when immediately issued after a START_COMMAND is expected
  # go only let a few cycles through, so we check less than 10

  def test_thread_profiling
    @agent.send(:check_for_agent_commands)
    sleep(1)
    NewRelic::Agent.shutdown

    profile_data = $collector.calls_for('profile_data')[0]
    assert_equal(666, profile_data[0])

    poll_count = profile_data[1][0][3]
    assert poll_count > 25, "Expected poll_count > 25, but was #{poll_count}"
  end

  def test_thread_profiling_can_stop
    @agent.send(:check_for_agent_commands)

    $collector.mock['get_agent_commands'] = [200, STOP_COMMAND]
    @agent.send(:check_for_agent_commands)

    sleep(0.1)
    NewRelic::Agent.shutdown

    profile_data = $collector.calls_for('profile_data')[0]
    assert_equal(666, profile_data[0])

    poll_count = profile_data[1][0][3]
    assert poll_count < 10, "Expected poll_count < 10, but was #{poll_count}"
  end
end
end

