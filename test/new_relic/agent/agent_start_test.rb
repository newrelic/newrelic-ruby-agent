require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper')) 
class NewRelic::Agent::AgentStartTest < Test::Unit::TestCase
  require 'new_relic/agent/agent'
  include NewRelic::Agent::Agent::Start

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
    control = mocked_control
    control.expects(:agent_enabled?).returns(false)
    assert disabled?
  end

  def test_disabled_negative
    control = mocked_control
    control.expects(:agent_enabled?).returns(true)
    assert !disabled?
  end

  def test_log_dispatcher_positive
    control = mocked_control
    log = mocked_log
    control.expects(:dispatcher).returns('Y U NO SERVE WEBPAGE')
    log.expects(:info).with("Dispatcher: Y U NO SERVE WEBPAGE")
    log_dispatcher
  end

  def test_log_dispatcher_negative
    control = mocked_control
    log = mocked_log
    control.expects(:dispatcher).returns('')
    log.expects(:info).with("Dispatcher: None detected.")
    log_dispatcher
  end

  def test_log_app_names
    control = mocked_control
    log = mocked_log
    control.expects(:app_names).returns(%w(zam zam zabam))
    log.expects(:info).with("Application: zam, zam, zabam")
    log_app_names
  end

  def test_apdex_f
    NewRelic::Control.instance.expects(:apdex_t).returns(10)
    assert_equal 40, apdex_f
  end

  def test_apdex_f_threshold_positive
    self.expects(:sampler_config).returns({'transaction_threshold' => 'apdex_f'})
    assert apdex_f_threshold?
  end

  def test_apdex_f_threshold_negative
    self.expects(:sampler_config).returns({'transaction_threshold' => 'WHEE'})
    assert !apdex_f_threshold?
  end

  def test_set_sql_recording_default
    self.expects(:sampler_config).returns({})
    self.expects(:log_sql_transmission_warning?)
    set_sql_recording!
    assert_equal :obfuscated, @record_sql, " should default to :obfuscated, was #{@record_sql}"
  end

  def test_set_sql_recording_none
    self.expects(:sampler_config).returns({'record_sql' => 'none'})
    self.expects(:log_sql_transmission_warning?)
    set_sql_recording!
    assert_equal :none, @record_sql, "should be set to :none, was #{@record_sql}"
  end
  
  def test_set_sql_recording_raw
    self.expects(:sampler_config).returns({'record_sql' => 'raw'})
    self.expects(:log_sql_transmission_warning?)
    set_sql_recording!
    assert_equal :raw, @record_sql, "should be set to :raw, was #{@record_sql}"
  end

  def test_log_sql_transmission_warning_negative
    log = mocked_log
    @record_sql = :obfuscated
    log.expects(:warn).never
    log_sql_transmission_warning?
  end

  def test_log_sql_transmission_warning_positive
    log = mocked_log
    @record_sql = :raw
    log.expects(:warn).once.with('Agent is configured to send raw SQL to RPM service')
    log_sql_transmission_warning?
  end

  def test_sampler_config
    control = mocked_control
    control.expects(:fetch).with('transaction_tracer', {})
    sampler_config
  end

  def test_config_transaction_tracer
    # needs more breakage!
    assert false
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

