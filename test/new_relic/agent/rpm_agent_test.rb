# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../../../test_helper', __FILE__)

class NewRelic::Agent::RpmAgentTest < Minitest::Test
  def setup
    NewRelic::Agent.manual_start
    @agent = NewRelic::Agent.instance
    @agent.stubs(:start_worker_thread)
  end

  def teardown
    NewRelic::Agent.instance.shutdown
    NewRelic::Agent.drop_buffered_data
  end

  def test_public_apis
    assert_raises(RuntimeError) do
      NewRelic::Agent.set_sql_obfuscator(:unknown) { |sql| puts sql }
    end

    ignore_called = false
    filter = Proc.new do |e|
      ignore_called = true
      nil
    end
    with_ignore_error_filter(filter) do
      NewRelic::Agent.notice_error(StandardError.new("message"), :request_params => {:x => "y"})
    end

    assert(ignore_called)
  end

  def test_startup_shutdown_real
    with_config(:agent_enabled => true, :monitor_mode => true) do
      NewRelic::Agent.manual_start :monitor_mode => true, :license_key => ('x' * 40)
      agent = NewRelic::Agent.instance
      assert agent.started?
      agent.shutdown
      refute agent.started?
    end
  end

  def test_manual_start
    NewRelic::Agent.instance.expects(:connect).once
    NewRelic::Agent.instance.expects(:start_worker_thread).once
    NewRelic::Agent.instance.instance_variable_set '@started', nil
    NewRelic::Agent.manual_start :monitor_mode => true, :license_key => ('x' * 40)
    NewRelic::Agent.shutdown
  end

  def test_post_fork_handler
    NewRelic::Agent.manual_start :monitor_mode => true, :license_key => ('x' * 40)
    NewRelic::Agent.after_fork
    NewRelic::Agent.after_fork
    NewRelic::Agent.shutdown
  end

  def test_manual_overrides
    NewRelic::Agent.manual_start :app_name => "testjobs"
    assert_equal "testjobs", NewRelic::Agent.config.app_names[0]
    NewRelic::Agent.shutdown
  end

  def test_agent_restart
    NewRelic::Agent.manual_start :app_name => "noapp"
    NewRelic::Agent.manual_start :app_name => "testjobs"
    assert_equal "testjobs", NewRelic::Agent.config.app_names[0]
    NewRelic::Agent.shutdown
  end

  def test_set_record_sql
    @agent.set_record_sql(false)
    assert !NewRelic::Agent.tl_is_sql_recorded?
    NewRelic::Agent.disable_sql_recording do
      assert_equal false, NewRelic::Agent.tl_is_sql_recorded?
      NewRelic::Agent.disable_sql_recording do
        assert_equal false, NewRelic::Agent.tl_is_sql_recorded?
      end
      assert_equal false, NewRelic::Agent.tl_is_sql_recorded?
    end
    assert !NewRelic::Agent.tl_is_sql_recorded?
    @agent.set_record_sql(nil)
  end

  def test_agent_version_string
    assert_match(/\d\.\d+\.\d+/, NewRelic::VERSION::STRING)
  end

  def test_record_transaction
    NewRelic::Agent.record_transaction 0.5, 'uri' => "/users/create?foo=bar"
  end
end
