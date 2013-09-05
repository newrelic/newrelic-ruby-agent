# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'/../test_helper'))

class NewRelic::ControlTest < Test::Unit::TestCase
  attr_reader :control

  def setup
    @control =  NewRelic::Control.instance
    raise 'oh geez, wrong class' unless NewRelic::Control.instance.is_a?(::NewRelic::Control::Frameworks::Test)
  end

  def shutdown
    NewRelic::Agent.shutdown
  end


  def test_test_config
    if defined?(::Rails) && ::Rails::VERSION::MAJOR.to_i == 4
      assert_equal :rails4, control.app
    elsif defined?(::Rails) && ::Rails::VERSION::MAJOR.to_i == 3
      assert_equal :rails3, control.app
    elsif defined?(::Rails)
      assert_equal :rails, control.app
    else
      assert_equal :test, control.app
    end
    assert_equal :test, control.framework
    assert("" == NewRelic::Agent.config[:dispatcher].to_s,
           "Expected dispatcher to be empty, but was #{NewRelic::Agent.config[:dispatcher].to_s}")
    assert !NewRelic::Agent.config[:monitor_mode]
    control.local_env
  end

  def test_settings_accessor
    assert_not_nil control.settings
  end

  def test_root
    assert File.directory?(NewRelic::Control.newrelic_root), NewRelic::Control.newrelic_root
    if defined?(Rails)
      assert File.directory?(File.join(NewRelic::Control.newrelic_root, "lib")), NewRelic::Control.newrelic_root +  "/lib"
    end
  end

  def test_info
    NewRelic::Agent.manual_start
    if defined?(Rails)
      assert_match /jdbc|postgres|mysql|sqlite/, NewRelic::EnvironmentReport.new["Database adapter"]
    end
  end

  def test_resolve_ip_for_localhost
    with_config(:ssl => false) do
      assert_equal nil, control.send(:convert_to_ip_address, 'localhost')
    end
  end

  def test_resolve_ip_for_non_existent_domain
    with_config(:ssl => false) do
      Resolv.stubs(:getaddress).raises(Resolv::ResolvError)
      IPSocket.stubs(:getaddress).raises(SocketError)
      assert_equal nil, control.send(:convert_to_ip_address, 'q1239988737.us')
    end
  end

  def test_resolves_valid_ip
    with_config(:ssl => false) do
      Resolv.stubs(:getaddress).with('collector.newrelic.com').returns('204.93.223.153')
      assert_equal '204.93.223.153', control.send(:convert_to_ip_address, 'collector.newrelic.com')
    end
  end

  def test_do_not_resolve_if_we_need_to_verify_a_cert
    with_config(:ssl => false) do
      assert_equal nil, control.send(:convert_to_ip_address, 'localhost')
    end
    with_config(:ssl => true) do
      assert_equal 'localhost', control.send(:convert_to_ip_address, 'localhost')
    end
  end

  def test_api_server_uses_configured_values
    control.instance_variable_set(:@api_server, nil)
    with_config(:api_host => 'somewhere', :api_port => 8080) do
      assert_equal 'somewhere', control.api_server.name
      assert_equal 8080, control.api_server.port
    end
  end

  def test_proxy_server_uses_configured_values
    control.instance_variable_set(:@proxy_server, nil)
    with_config(:proxy_host => 'proxytown', :proxy_port => 81) do
      assert_equal 'proxytown', control.proxy_server.name
      assert_equal 81, control.proxy_server.port
    end
  end

  def test_server_from_host_uses_configured_values
    with_config(:host => 'donkeytown', :port => 8080) do
      assert_equal 'donkeytown', control.server_from_host.name
      assert_equal 8080, control.server_from_host.port
    end
  end

  class FakeResolv
    def self.getaddress(host)
      raise 'deliberately broken'
    end
  end

  def test_resolve_ip_with_broken_dns
    # Here be dragons: disable the ruby DNS lookup methods we use so
    # that it will actually fail to resolve.
    old_resolv = Resolv
    old_ipsocket = IPSocket
    Object.instance_eval { remove_const :Resolv}
    Object.instance_eval {remove_const:'IPSocket' }

    with_config(:ssl => false) do
      assert_equal(nil, control.send(:convert_to_ip_address, 'collector.newrelic.com'), "DNS is down, should be no IP for server")
    end

    Object.instance_eval {const_set('Resolv', old_resolv); const_set('IPSocket', old_ipsocket)}
    # these are here to make sure that the constant tomfoolery above
    # has not broket the system unduly
    assert_equal old_resolv, Resolv
    assert_equal old_ipsocket, IPSocket
  end

  def test_transaction_threshold__override
    with_config(:transaction_tracer => { :transaction_threshold => 1}) do
      assert_equal 1, NewRelic::Agent.config[:'transaction_tracer.transaction_threshold']
    end
  end

  def test_transaction_tracer_disabled
    with_config(:'transaction_tracer.enabled' => false,
                :developer_mode => false, :monitor_mode => true) do
      assert(!NewRelic::Agent::Agent.instance.transaction_sampler.enabled?,
             'transaction tracer enabled when config calls for disabled')
    end
  end

  def test_sql_tracer_disabled
    with_config(:'slow_sql.enabled' => false, :monitor_mode => true) do
      assert(!NewRelic::Agent::Agent.instance.sql_sampler.enabled?,
             'sql tracer enabled when config calls for disabled')
    end
  end

  def test_sql_tracer_disabled_with_record_sql_false
    with_config(:slow_sql => { :enabled => true, :record_sql => 'off' }) do
      assert(!NewRelic::Agent::Agent.instance.sql_sampler.enabled?,
             'sql tracer enabled when config calls for disabled')
    end
  end

  def test_sql_tracer_disabled_when_tt_disabled
    with_config(:'transaction_tracer.enabled' => false,
                :'slow_sql.enabled' => true,
                :developer_mode => false, :monitor_mode => true) do
      assert(!NewRelic::Agent::Agent.instance.sql_sampler.enabled?,
             'sql enabled when transaction tracer disabled')
    end
  end

  def test_sql_tracer_disabled_when_tt_disabled_by_server
    with_config({:'slow_sql.enabled' => true,
                  :'transaction_tracer.enabled' => true,
                  :monitor_mode => true}, :level => 2) do
      NewRelic::Agent.instance.finish_setup('collect_traces' => false)

      assert(!NewRelic::Agent::Agent.instance.sql_sampler.enabled?,
             'sql enabled when tracing disabled by server')
    end
  end

  def test_init_plugin_loads_samplers_enabled
    NewRelic::Agent.shutdown
    with_config(:disable_samplers => false, :agent_enabled => true) do
      NewRelic::Control.instance.init_plugin
      assert NewRelic::Agent.instance.harvest_samplers.any?
    end
  end

  def test_init_plugin_loads_samplers_disabled
    NewRelic::Agent.shutdown
    with_config(:disable_samplers => true, :agent_enabled => true) do
      NewRelic::Control.instance.init_plugin
      assert !NewRelic::Agent.instance.harvest_samplers.any?
    end
  end
end
