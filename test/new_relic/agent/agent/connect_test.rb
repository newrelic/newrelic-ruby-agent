require File.expand_path(File.join(File.dirname(__FILE__),'..', '..', '..','test_helper'))
require 'new_relic/agent/agent'
require 'ostruct'

class NewRelic::Agent::Agent::ConnectTest < Test::Unit::TestCase
  include NewRelic::Agent::Agent::Connect

  def setup
    @connected = nil
    @keep_retrying = nil
    @connect_attempts = 1
    @connect_retry_period = 0
    @transaction_sampler = NewRelic::Agent::TransactionSampler.new
    @sql_sampler = NewRelic::Agent::SqlSampler.new
    @error_collector = NewRelic::Agent::ErrorCollector.new
    server = NewRelic::Control::Server.new('localhost', 30303)
    @service = NewRelic::Agent::NewRelicService.new('abcdef', server)
    @test_config = { :developer_mode => true }
    NewRelic::Agent.config.apply_config(@test_config)
  end

  def teardown
    NewRelic::Agent.config.remove_config(@test_config)
  end

  def control
    fake_control = OpenStruct.new('local_env' => OpenStruct.new('snapshot' => []))
    fake_control.instance_eval do
      def [](key)
        return nil
      end
    end
    fake_control
  end

  def test_tried_to_connect?
    # base case, should default to false
    assert !tried_to_connect?({})
  end

  def test_tried_to_connect_connected
    # is true if connected is true.
    @connected = true
    assert tried_to_connect?({})
  end

  def test_tried_to_connect_forced
    # is false if force_reconnect is true
    assert !tried_to_connect?({:force_reconnect => true})
  end

  def test_should_keep_retrying_base
    # default to true
    should_keep_retrying?({})
    assert @keep_retrying, "should keep retrying by default"
  end

  def test_should_keep_retrying_option_true
    # should be true if keep_retrying is true
    should_keep_retrying?({:keep_retrying => true})
  end

  def test_get_retry_period
    (1..6).each do |x|
      @connect_attempts = x
      assert_equal get_retry_period, x * 60, "should be #{x} minutes"
    end
    @connect_attempts = 100
    assert_equal get_retry_period, 600, "should max out at 10 minutes after 6 tries"
  end

  def test_increment_retry_period
    @connect_retry_period = 0
    @connect_attempts = 1
    assert_equal 0, connect_retry_period
    increment_retry_period!
    assert_equal 60, connect_retry_period
  end

  def test_should_retry_true
    @keep_retrying = true
    @connect_attempts = 1
    self.expects(:increment_retry_period!).once
    assert should_retry?, "should retry in this circumstance"
    assert_equal 2, @connect_attempts, "should be on the second attempt"
  end

  def test_should_retry_false
    @keep_retrying = false
    self.expects(:disconnect).once
    assert !should_retry?
  end

  def test_disconnect
    assert disconnect
  end

  def test_attr_accessor_connect_retry_period
    assert_accessor(:connect_retry_period)
  end

  def test_attr_accessor_connect_attempts
    assert_accessor(:connect_attempts)
  end

  def test_log_error
    error = StandardError.new("message")

    expects_logging(:error, 
      includes("Error establishing connection with New Relic Service"), \
      instance_of(StandardError))

    log_error(error)
  end

  def test_handle_license_error
    error = mock(:message => "error message")
    self.expects(:disconnect).once
    handle_license_error(error)
  end

  def test_environment_for_connect_positive
    fake_env = stub('local_env', :discovered_dispatcher => nil)
    fake_env.expects(:snapshot).returns("snapshot")
    NewRelic::Control.instance.expects(:local_env).at_least_once.returns(fake_env)
    with_config(:send_environment_info => true) do
      assert_equal 'snapshot', environment_for_connect
    end
  end

  def test_environment_for_connect_negative
    with_config(:send_environment_info => false) do
      assert_equal [], environment_for_connect
    end
  end

  def test_connect_settings
    control = mocked_control
    NewRelic::Agent.config.expects(:app_names)
    self.expects(:environment_for_connect)
    keys = %w(pid host app_name language agent_version environment settings)
    value = connect_settings
    keys.each do |k|
      assert(value.has_key?(k.to_sym), "should include the key #{k}")
    end
  end

  def test_configure_transaction_tracer_with_random_sampling
    with_config(:'transaction_tracer.transaction_threshold' => 5,
                :'transaction_tracer.random_sample' => true) do
      sample = TransactionSampleTestHelper.make_sql_transaction
      @transaction_sampler.store_sample(sample)

      assert_equal sample, @transaction_sampler.instance_variable_get(:@random_sample)
    end
  end

  def test_configure_transaction_tracer_positive
    with_config(:'transaction_tracer.enabled' => true) do
      assert @transaction_sampler.enabled?
    end
  end

  def test_configure_transaction_tracer_negative
    with_config(:'transaction_tracer.enabled' => false) do
      assert @transaction_sampler.enabled?
    end
  end

  def test_configure_transaction_tracer_server_disabled
    config = NewRelic::Agent::Configuration::ServerSource.new('collect_traces' => false,
                                                              'developer_mode' => false)
    with_config(config) do
      assert !@transaction_sampler.enabled?
    end
  end

  def test_apdex_f
    with_config(:apdex_t => 10) do
      assert_equal 40, apdex_f
    end
  end

  def test_set_sql_recording_default
    with_config(:'transaction_tracer.record_sql' => 'obfuscated') do
      assert_equal(:obfuscated, NewRelic::Agent::Database.record_sql_method,
                   "should default to :obfuscated, was #{NewRelic::Agent::Database.record_sql_method}")
    end
  end

  def test_set_sql_recording_off
    with_config(:'transaction_tracer.record_sql' => 'off') do
      assert_equal(:off, NewRelic::Agent::Database.record_sql_method,
                   "should be set to :off, was #{NewRelic::Agent::Database.record_sql_method}")
    end
  end

  def test_set_sql_recording_none
    with_config(:'transaction_tracer.record_sql' => 'none') do
      assert_equal(:off, NewRelic::Agent::Database.record_sql_method,
                   "should be set to :off, was #{NewRelic::Agent::Database.record_sql_method}")
    end
  end

  def test_set_sql_recording_raw
    with_config(:'transaction_tracer.record_sql' => 'raw') do
      assert_equal(:raw, NewRelic::Agent::Database.record_sql_method,
                   "should be set to :raw, was #{NewRelic::Agent::Database.record_sql_method}")
    end
  end

  def test_set_sql_recording_falsy
    with_config(:'transaction_tracer.record_sql' => false) do
      assert_equal(:off, NewRelic::Agent::Database.record_sql_method,
                   "should be set to :off, was #{NewRelic::Agent::Database.record_sql_method}")
    end
  end

  def test_query_server_for_configuration
    self.expects(:connect_to_server).returns("so happy")
    self.expects(:finish_setup).with("so happy")
    query_server_for_configuration
  end

  def test_connect_to_server_gets_config_from_collector
    NewRelic::Agent.manual_start
    service = NewRelic::FakeService.new
    NewRelic::Agent::Agent.instance.service = service
    service.mock['connect'] = {'agent_run_id' => 23, 'config' => 'a lot'}

    response = NewRelic::Agent.agent.connect_to_server

    assert_equal 23, response['agent_run_id']
    assert_equal 'a lot', response['config']

    NewRelic::Agent.shutdown
  end

  def test_finish_setup
    config = {
      'agent_run_id' => 'fishsticks',
      'collect_traces' => true,
      'collect_errors' => true,
      'sample_rate' => 10,
      'cross_process_id' => '1#234',
      'encoding_key'     => 'a' * 30,
      'agent_config' => { 'transaction_tracer.record_sql' => 'raw' }
    }
    self.expects(:log_connection!).with(config)
    @transaction_sampler = stub('transaction sampler', :configure! => true,
                                :config => {})
    @sql_sampler = stub('sql sampler', :configure! => true)
    with_config(:'transaction_tracer.enabled' => true) do
      finish_setup(config)
      assert_equal 'fishsticks', @service.agent_id
      assert_equal '1#234', @cross_process_id
      assert_equal 'a'  * 30, @cross_process_encoding_key
      assert_equal [97] * 30, @cross_process_encoding_bytes
      assert_equal 'raw', NewRelic::Agent.config[:'transaction_tracer.record_sql']
    end
  end

  def test_get_bytes_with_nil
    assert_equal [], get_bytes(nil)
  end

  def test_logging_collector_messages
    NewRelic::Agent.manual_start
    service = NewRelic::FakeService.new
    NewRelic::Agent::Agent.instance.service = service
    service.mock['connect'] = {
      'agent_run_id' => 23, 'config' => 'a lot',
      'messages' => [{ 'message' => 'beep boop', 'level' => 'INFO' },
                     { 'message' => 'ha cha cha', 'level' => 'WARN' }]
    }

    expects_logging(:info, 'beep boop')
    expects_logging(:warn, 'ha cha cha')

    NewRelic::Agent.agent.query_server_for_configuration
    NewRelic::Agent.shutdown
  end

  def test_finish_setup_without_config
    @service.agent_id = 'blah'
    finish_setup(nil)
    assert_equal 'blah', @service.agent_id
  end

  # no idea why this test leaks in Rails 2.0
  # will be moved to a multiverse test eventually anyway
  if !Rails::VERSION::STRING =~ /2\.0.*/
    def test_set_apdex_t_from_server
      service = NewRelic::FakeService.new
      NewRelic::Agent::Agent.instance.service = service
      service.mock['connect'] = { 'apdex_t' => 0.5 }
      with_config(:sync_startup => true, :monitor_mode => true,
                  :license_key => 'a' * 40) do
        NewRelic::Agent.manual_start
        assert_equal 0.5, NewRelic::Agent.config[:apdex_t]
        NewRelic::Agent.shutdown
      end
    end
  end

  private

  def mocked_control
    fake_control = mock('control')
    self.stubs(:control).returns(fake_control)
    fake_control
  end

  def mocked_error_collector
    fake_collector = mock('error collector')
    self.stubs(:error_collector).returns(fake_collector)
    fake_collector
  end

  def assert_accessor(sym)
    var_name = "@#{sym}"
    instance_variable_set(var_name, 1)
    assert (self.send(sym) == 1)
    self.send(sym.to_s + '=', 10)
    assert (instance_variable_get(var_name) == 10)
  end
end
