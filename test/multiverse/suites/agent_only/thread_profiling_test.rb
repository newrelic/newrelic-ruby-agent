# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# https://newrelic.atlassian.net/wiki/display/eng/Agent+Thread+Profiling
# https://newrelic.atlassian.net/browse/RUBY-917

if RUBY_VERSION >= '1.9'

require 'thread'

class ThreadProfilingTest < Minitest::Test

  include MultiverseHelpers

  setup_and_teardown_agent(:'thread_profiler.enabled' => true) do |collector|
    collector.stub('connect', {"agent_run_id" => 666 })
    collector.stub('get_agent_commands', [])
    collector.stub('agent_command_results', [])
  end

  def after_setup
    agent.service.request_timeout = 0.5
    agent.service.agent_id = 666

    @thread_profiler_session = agent.agent_command_router.thread_profiler_session
    @threads = []
  end

  def after_teardown
    @threads.each { |t| t.kill }
    @threads = nil
  end

  START_COMMAND = [[666,{
      "name" => "start_profiler",
      "arguments" => {
        "profile_id" => -1,
        "sample_period" => 0.01,
        "duration" => 0.75,
        "only_runnable_threads" => false,
        "only_request_threads" => false,
        "profile_agent_code" => true
      }
    }]]

  STOP_COMMAND = [[666,{
      "name" => "stop_profiler",
      "arguments" => {
        "profile_id" => -1,
        "report_data" => true
      }
    }]]

  # These are potentially fragile for being timing based
  # START_COMMAND with 0.01 sampling and 0.5 duration expects to get
  # roughly 50 polling cycles in. We check signficiantly less than that.

  # STOP_COMMAND when immediately issued after a START_COMMAND is expected
  # go only let a few cycles through, so we check less than 10

  def test_thread_profiling
    run_transaction_in_thread(:controller)
    run_transaction_in_thread(:task)

    issue_command(START_COMMAND)

    let_it_finish

    profile_data = $collector.calls_for('profile_data')[0]
    assert_equal('666', profile_data.run_id, "Missing run_id, profile_data was #{profile_data.inspect}")
    assert(profile_data.sample_count >= 2, "Expected sample_count >= 2, but was #{profile_data.sample_count}")

    assert_saw_traces(profile_data, "OTHER")
    assert_saw_traces(profile_data, "AGENT")
    assert_saw_traces(profile_data, "REQUEST")
    assert_saw_traces(profile_data, "BACKGROUND")
  end

  def test_thread_profiling_can_stop
    issue_command(START_COMMAND)
    issue_command(STOP_COMMAND)

    # No wait needed, should be immediately ready to harvest
    assert @thread_profiler_session.ready_to_harvest?
    harvest

    profile_data = $collector.calls_for('profile_data')[0]
    assert_equal('666', profile_data.run_id, "Missing run_id, profile_data was #{profile_data.inspect}")
    assert(profile_data.sample_count < 50, "Expected sample_count < 50, but was #{profile_data.sample_count}")
  end

  def issue_command(cmd)
    $collector.stub('get_agent_commands', cmd)
    agent.send(:check_for_and_handle_agent_commands)
    $collector.stub('get_agent_commands', [])
  end

  # Runs a thread we expect to span entire test and be killed at the end
  def run_transaction_in_thread(category)
    q = Queue.new
    @threads ||= []
    @threads << Thread.new do
      in_transaction(:category => category) do
        q.push('.')
        sleep # sleep until explicitly woken in join_background_threads
      end
    end
    q.pop # block until the thread has had a chance to start up
  end

  def let_it_finish
    wait_for_backtrace_service_poll(:timeout => 10.0, :iterations => 1)
    harvest
    join_background_threads
  end

  def join_background_threads
    if @threads
      @threads.each do |thread|
        thread.run
        thread.join
      end
    end
  end

  def harvest
    agent.shutdown
  end

  def assert_saw_traces(profile_data, type)
    assert_kind_of Hash, profile_data.traces
    traces_for_type = profile_data.traces[type]
    assert traces_for_type, "Missing key for type #{type} in profile_data"
    assert_kind_of Array, traces_for_type
    assert !profile_data.traces[type].empty?, "Zero #{type} traces seen"
  end

end
end
