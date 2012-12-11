require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
class NewRelic::Agent::Agent::StartTest < Test::Unit::TestCase
  require 'new_relic/agent/agent'
  include NewRelic::Agent::Agent::Start

  def setup
    ENV['NEW_RELIC_APP_NAME'] = 'start_test'
    NewRelic::Agent.reset_config
  end

  def teardown
    ENV['NEW_RELIC_APP_NAME'] = nil
    NewRelic::Agent.reset_config
  end

  def test_already_started_positive
    control = mocked_control
    control.expects(:log!).with("Agent Started Already!", :error)
    self.expects(:started?).returns(true)
    assert already_started?, "should have already started"
  end

  def test_already_started_negative
    self.expects(:started?).returns(false)
    assert !already_started?
  end

  def test_disabled_positive
    with_config(:agent_enabled => false) do
      assert disabled?
    end
  end

  def test_disabled_negative
    with_config(:agent_enabled => true) do
      assert !disabled?
    end
  end

  def test_log_dispatcher_positive
    log = mocked_log
    with_config(:dispatcher => 'Y U NO SERVE WEBPAGE') do
      log.expects(:info).with("Dispatcher: Y U NO SERVE WEBPAGE")
      log_dispatcher
    end
  end

  def test_log_dispatcher_negative
    log = mocked_log
    with_config(:dispatcher => '') do
      log.expects(:info).with("No dispatcher detected.")
      log_dispatcher
    end
  end

  def test_log_app_names_string
    with_config(:app_name => 'zam;zam;zabam') do
      log = mocked_log
      log.expects(:info).with("Application: zam, zam, zabam")
      log_app_names
    end
  end

  def test_log_app_names_array
    with_config(:app_name => ['zam', 'zam', 'zabam']) do
      log = mocked_log
      log.expects(:info).with("Application: zam, zam, zabam")
      log_app_names
    end
  end

  def test_log_app_names_with_env_var
    # bad app name after env - used to cover the yaml config
    with_config({:app_name => false}, 1) do
      log = mocked_log
      log.expects(:info).with("Application: start_test") # set in setup
      log_app_names
    end
  end

  def test_log_app_names_with_unknown
    with_config(:app_name => false) do
      log = mocked_log
      log.expects(:error).with('Unable to determine application name. Please set the application name in your newrelic.yml or in a NEW_RELIC_APP_NAME environment variable.')
      log_app_names
    end
  end

  def test_check_config_and_start_agent_disabled
    self.expects(:monitoring?).returns(false)
    check_config_and_start_agent
  end

  def test_check_config_and_start_agent_incorrect_key
    self.expects(:monitoring?).returns(true)
    self.expects(:has_correct_license_key?).returns(false)
    check_config_and_start_agent
  end

  def test_check_config_and_start_agent_forking
    self.expects(:monitoring?).returns(true)
    self.expects(:has_correct_license_key?).returns(true)
    self.expects(:using_forking_dispatcher?).returns(true)
    check_config_and_start_agent
  end

  def test_check_config_and_start_agent_normal
    self.expects(:start_worker_thread)
    self.expects(:install_exit_handler)
    with_config(:sync_startup => false, :monitor_mode => true, :license_key => 'a' * 40) do
      check_config_and_start_agent
    end
  end

  def test_check_config_and_start_agent_sync
    self.expects(:connect_in_foreground)
    self.expects(:start_worker_thread)
    self.expects(:install_exit_handler)
    with_config(:sync_startup => true, :monitor_mode => true, :license_key => 'a' * 40) do
      check_config_and_start_agent
    end
  end

  def test_connect_in_foreground
    self.expects(:connect).with({:keep_retrying => false })
    connect_in_foreground
  end

  def at_exit
    yield
  end
  private :at_exit

  def test_install_exit_handler_positive
    NewRelic::LanguageSupport.expects(:using_engine?).with('rbx').returns(false)
    NewRelic::LanguageSupport.expects(:using_engine?).with('jruby').returns(false)
    self.expects(:using_sinatra?).returns(false)
    # we are overriding at_exit above, to immediately return, so we can
    # test the shutdown logic. It's somewhat unfortunate, but we can't
    # kill the interpreter during a test.
    self.expects(:shutdown)
    with_config(:send_data_on_exit => true) do
      install_exit_handler
    end
  end

  def test_install_exit_handler_negative
    with_config(:send_data_on_exit => false) do
      install_exit_handler
    end
    # should not raise excpetion
  end

  def test_install_exit_handler_weird_ruby
    with_config(:send_data_one_exit => true) do
      NewRelic::LanguageSupport.expects(:using_engine?).with('rbx').returns(false)
      NewRelic::LanguageSupport.expects(:using_engine?).with('jruby').returns(false)
      self.expects(:using_sinatra?).returns(true)
      install_exit_handler
      NewRelic::LanguageSupport.expects(:using_engine?).with('rbx').returns(false)
      NewRelic::LanguageSupport.expects(:using_engine?).with('jruby').returns(true)
      install_exit_handler
      NewRelic::LanguageSupport.expects(:using_engine?).with('rbx').returns(true)
      install_exit_handler
    end
  end

  def test_notify_log_file_location_positive
    log = mocked_log
    NewRelic::Control.instance.expects(:log_file).returns('./')
    log.expects(:send).with(:info, "Agent Log at ./")
    notify_log_file_location
  end

  def test_notify_log_file_location_negative
    log = mocked_log
    NewRelic::Control.instance.expects(:log_file).returns(nil)
    notify_log_file_location
  end

  def test_monitoring_positive
    with_config(:monitor_mode => true) do
      log = mocked_log
      assert monitoring?
    end
  end

  def test_monitoring_negative
    log = mocked_log
    with_config(:monitor_mode => false) do
      log.expects(:send).with(:warn, "Agent configured not to send data in this environment.")
      assert !monitoring?
    end
  end

  def test_has_license_key_positive
    with_config(:license_key => 'a' * 40) do
      assert has_license_key?
    end
  end

  def test_has_license_key_negative
    with_config(:license_key => false) do
      log = mocked_log
      log.expects(:send).with(:warn, 'No license key found in newrelic.yml config.')
      assert !has_license_key?
    end
  end

  def test_has_correct_license_key_positive
    self.expects(:has_license_key?).returns(true)
    self.expects(:correct_license_length).returns(true)
    assert has_correct_license_key?
  end

  def test_has_correct_license_key_negative
    self.expects(:has_license_key?).returns(false)
    assert !has_correct_license_key?
  end

  def test_correct_license_length_positive
    with_config(:license_key => 'a' * 40) do
      assert correct_license_length
    end
  end

  def test_correct_license_length_negative
    with_config(:license_key => 'a' * 30) do
      log = mocked_log
      log.expects(:send).with(:error, "Invalid license key: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
      assert !correct_license_length
    end
  end

  def test_using_forking_dispatcher_positive
    with_config(:dispatcher => :passenger) do
      log = mocked_log
      log.expects(:send).with(:info, "Connecting workers after forking.")
      assert using_forking_dispatcher?
    end
  end

  def test_using_forking_dispatcher_negative
    with_config(:dispatcher => :frobnitz) do
      assert !using_forking_dispatcher?
    end
  end

  def test_log_unless_positive
    # should not log
    assert log_unless(true, :warn, "DURRR")
  end
  def test_log_unless_negative
    # should log
    log = mocked_log
    log.expects(:send).with(:warn, "DURRR")
    assert !log_unless(false, :warn, "DURRR")
  end

  def test_log_if_positive
    log = mocked_log
    log.expects(:send).with(:warn, "WHEE")
    assert log_if(true, :warn, "WHEE")
  end

  def test_log_if_negative
    assert !log_if(false, :warn, "WHEE")
  end

  private

  def mocked_log
    fake_log = mock('log')
    self.stubs(:log).returns(fake_log)
    fake_log
  end


  def mocked_control
    fake_control = mock('control')
    self.stubs(:control).returns(fake_control)
    fake_control
  end
end

