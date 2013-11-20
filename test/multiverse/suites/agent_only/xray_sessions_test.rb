# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# https://newrelic.atlassian.net/wiki/display/eng/Agent+Thread+Profiling
# https://newrelic.atlassian.net/browse/RUBY-917

if RUBY_VERSION >= '1.9'

require 'rack/test'
require 'multiverse_helpers'
require './testing_app'

class XraySessionsTest < MiniTest::Unit::TestCase

  AGENT_RUN_ID = 123

  include MultiverseHelpers
  include Rack::Test::Methods

  setup_and_teardown_agent() do |collector|
    collector.stub('connect', {"agent_run_id" => AGENT_RUN_ID })
  end

  def after_setup
    agent.service.request_timeout = 0.5
    agent.service.agent_id = AGENT_RUN_ID
  end

  def app
    @app ||= TestingApp.new
  end

  def test_tags_transaction_traces_with_xray_id
    session = build_xray_session('key_transaction_name' => 'Controller/Rack/A')
    with_xray_sessions(session) do
      5.times { get '/?transaction_name=A' }
      trigger_harvest
    end

    posts = $collector.calls_for('transaction_sample_data')
    assert_equal(1, posts.size, "Expected exactly one transaction_sample_data post")

    traces = posts.first.samples
    assert_equal(5, traces.size)
    assert traces.all? { |t| t.metric_name == 'Controller/Rack/A' }
    assert traces.all? { |t| t.xray_id == session['x_ray_id'] }
  end

  def test_does_not_collect_traces_for_non_xrayed_transactions
    session = build_xray_session('key_transaction_name' => 'Controller/Rack/A')
    with_xray_sessions(session) do
      get '/?transaction_name=OtherThing'
      get '/?transaction_name=A'
      trigger_harvest
    end

    posts = $collector.calls_for('transaction_sample_data')
    assert_equal(1, posts.size, "Expected exactly one transaction_sample_data post")

    # We expect exactly one transaction trace, for A only
    assert_equal(1, posts.first.samples.size)
  end

  def test_gathers_transaction_traces_from_multiple_concurrent_xray_sessions
    sessionA = build_xray_session('x_ray_id' => 12, 'key_transaction_name' => 'Controller/Rack/A')
    sessionB = build_xray_session('x_ray_id' => 13, 'key_transaction_name' => 'Controller/Rack/B')

    with_xray_sessions(sessionA, sessionB) do
      2.times do
        get '/?transaction_name=A'
        get '/?transaction_name=B'
      end
      trigger_harvest
    end

    posts = $collector.calls_for('transaction_sample_data')
    assert_equal(1, posts.size, "Expected exactly one transaction_sample_data post")

    traces = posts.first.samples
    assert_equal(4, traces.size)

    tracesA = traces.select { |t| t.metric_name == 'Controller/Rack/A' }
    tracesB = traces.select { |t| t.metric_name == 'Controller/Rack/B' }
    assert_equal(2, tracesA.size, "Expected 2 traces for transaction A")
    assert_equal(2, tracesB.size, "Expected 2 traces for transaction B")
  end

  def test_gathers_thread_profiles
    session = build_xray_session('key_transaction_name' => 'Controller/Rack/A')
    with_xray_sessions(session) do
      wait_for_backtrace_service_poll
      get '/?transaction_name=A&sleep=1'
      trigger_harvest
    end

    # assert that a thread profile was submitted
    posts = $collector.calls_for('profile_data')
    assert_equal(1, posts.size, "Expected exactly one profile_data post")

    profile_data_post = posts.first
    assert(profile_data_post.sample_count > 1, "Expected at least one sample")
    assert_saw_traces(profile_data_post, 'REQUEST')
  end

  ## Helpers

  def next_xray_session_id
    @xray_session_id ||= 0
    @xray_session_id += 1
    @xray_session_id
  end

  def build_xray_session(overrides={})
    defaults = {
      "x_ray_id"              => next_xray_session_id,
      "xray_session_name"     => "Test XRay Session",
      "key_transaction_name"  => "Controller/Rack/Transaction",
      "requested_trace_count" => 10,
      "duration"              => 100,
      "sample_period"         => 0.1,
      "run_profiler"          => true
    }
    defaults.merge(overrides)
  end

  def build_active_xrays_command(active_xray_ids)
    [[
      AGENT_RUN_ID,
      {
        'name' => 'active_xray_sessions',
        'arguments' => { 'xray_ids' => active_xray_ids }
      }
    ]]
  end

  def with_xray_sessions(*xray_metadatas)
    xray_session_ids = xray_metadatas.map { |m| m['x_ray_id'] }
    activate_cmd = build_active_xrays_command(xray_session_ids)
    
    $collector.stub('get_xray_metadata', xray_metadatas)
    issue_command(activate_cmd)

    yield

    deactivate_cmd = build_active_xrays_command([])
    issue_command(deactivate_cmd)
  end

  def issue_command(cmd)
    $collector.stub('get_agent_commands', cmd)
    agent.send(:check_for_and_handle_agent_commands)
  end

  def trigger_harvest
    agent.send(:transmit_data)
  end

  def assert_saw_traces(profile_data, type)
    assert !profile_data.traces[type].empty?, "Missing #{type} traces"
  end

end
end
