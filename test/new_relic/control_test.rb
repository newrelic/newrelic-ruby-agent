# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'/../test_helper'))

class NewRelic::ControlTest < Minitest::Test
  attr_reader :control

  def setup
    @control =  NewRelic::Control.instance
    raise 'oh geez, wrong class' unless NewRelic::Control.instance.is_a?(::NewRelic::Control::Frameworks::Test)
    NewRelic::Agent.config.reset_to_defaults
  end

  def shutdown
    NewRelic::Agent.shutdown
  end

  def test_settings_accessor
    refute_nil control.settings
  end

  def test_root
    assert File.directory?(NewRelic::Control.newrelic_root), NewRelic::Control.newrelic_root
    if defined?(Rails::VERSION)
      assert File.directory?(File.join(NewRelic::Control.newrelic_root, "lib")), NewRelic::Control.newrelic_root +  "/lib"
    end
  end

  def test_info
    NewRelic::Agent.manual_start
    if defined?(Rails::VERSION)
      assert_match(/jdbc|postgres|mysql|sqlite/, NewRelic::EnvironmentReport.new["Database adapter"])
    end
  end

  def test_api_server_uses_configured_values
    control.instance_variable_set(:@api_server, nil)
    with_config(:api_host => 'somewhere', :api_port => 8080) do
      assert_equal 'somewhere', control.api_server.name
      assert_equal 8080, control.api_server.port
    end
  end

  def test_server_from_host_uses_configured_values
    with_config(:host => 'donkeytown', :port => 8080) do
      assert_equal 'donkeytown', control.server_from_host.name
      assert_equal 8080, control.server_from_host.port
    end
  end

  def test_transaction_threshold__override
    with_config(:transaction_tracer => { :transaction_threshold => 1}) do
      assert_equal 1, NewRelic::Agent.config[:'transaction_tracer.transaction_threshold']
    end
  end

  def test_transaction_tracer_disabled
    with_config(:'transaction_tracer.enabled' => false,
                :developer_mode => false, :monitor_mode => true) do
      assert(!NewRelic::Agent.instance.transaction_sampler.enabled?,
             'transaction tracer enabled when config calls for disabled')
    end
  end

  def test_sql_tracer_disabled
    with_config(:'slow_sql.enabled' => false, :monitor_mode => true) do
      assert(!NewRelic::Agent.instance.sql_sampler.enabled?,
             'sql tracer enabled when config calls for disabled')
    end
  end

  def test_sql_tracer_disabled_with_record_sql_false
    with_config(:slow_sql => { :enabled => true, :record_sql => 'off' }) do
      refute NewRelic::Agent.instance.sql_sampler.enabled?,
             'sql tracer enabled when config calls for disabled'
    end
  end

  def test_sql_tracer_disabled_when_tt_disabled
    with_config(:'transaction_tracer.enabled' => false,
                :'slow_sql.enabled' => true,
                :developer_mode => false, :monitor_mode => true) do
      refute NewRelic::Agent.instance.sql_sampler.enabled?,
             'sql enabled when transaction tracer disabled'
    end
  end

  def test_sql_tracer_disabled_when_tt_disabled_by_server
    with_config_low_priority({
                 :'slow_sql.enabled'           => true,
                 :'transaction_tracer.enabled' => true,
                 :monitor_mode                 => true}) do
      NewRelic::Agent.instance.finish_setup('collect_traces' => false)

      refute NewRelic::Agent::Agent.instance.sql_sampler.enabled?,
             'sql enabled when tracing disabled by server'
    end
  end

  def test_init_plugin_loads_samplers_enabled
    reset_agent

    with_config(:disable_samplers       => false,
                :disable_harvest_thread => true,
                :agent_enabled          => true,
                :monitor_mode           => true,
                :license_key            => 'a'*40) do
      NewRelic::Control.instance.init_plugin
      assert NewRelic::Agent.instance.harvest_samplers.any?
    end
  end

  def test_init_plugin_loads_samplers_disabled
    reset_agent

    with_config(:disable_samplers       => true,
                :disable_harvest_thread => true,
                :agent_enabled          => true,
                :monitor_mode           => true,
                :license_key            => 'a'*40) do
      NewRelic::Control.instance.init_plugin
      refute NewRelic::Agent.instance.harvest_samplers.any?
    end
  end

  def test_agent_not_starting_does_not_load_samplers
    reset_agent

    NewRelic::Agent.instance.stubs(:defer_for_delayed_job?).returns(true)

    with_config(:disable_samplers       => false,
                :disable_harvest_thread => true,
                :agent_enabled          => true,
                :monitor_mode           => true,
                :license_key            => 'a'*40) do
      NewRelic::Control.instance.init_plugin
      refute NewRelic::Agent.instance.already_started?
      refute NewRelic::Agent.instance.harvest_samplers.any?
    end
  end

  def test_agent_starting_after_fork_does_load_samplers
    reset_agent

    NewRelic::Agent.instance.stubs(:defer_for_delayed_job?).returns(true)

    with_config(:disable_samplers       => false,
                :disable_harvest_thread => true,
                :agent_enabled          => true,
                :monitor_mode           => true,
                :license_key            => 'a'*40) do
      NewRelic::Control.instance.init_plugin
      NewRelic::Agent.instance.stubs(:defer_for_delayed_job?).returns(false)
      NewRelic::Agent.after_fork
      assert NewRelic::Agent.instance.already_started?
      assert NewRelic::Agent.instance.harvest_samplers.any?
    end
  end

  def reset_agent
    NewRelic::Agent.shutdown
    NewRelic::Agent.instance.harvest_samplers.clear
    NewRelic::Agent.instance.instance_variable_set(:@connect_state, :pending)
    NewRelic::Agent.instance.instance_variable_set(:@worker_thread, nil)
    NewRelic::Agent.instance.harvester.instance_variable_set(:@starting_pid, nil)
  end
end
