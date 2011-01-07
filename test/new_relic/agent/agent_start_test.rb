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
    control.expects(:app_names).returns([zam, zam, zabam])
    log.expects(:info).with("Application: zam, zam, zabam")
    log_app_names
  end

  def test_config_transaction_tracer
    # needs more breakage!
    assert false
  end
  
  
  private

  def mocked_log
    log = mock('log')
    self.stub(:log).returns(log)
    log
  end


  def mocked_control
    control = mock('control')
    self.stub(:control).returns(control)
    control
  end
end

