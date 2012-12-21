require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

class NewRelic::Agent::Instrumentation::BrowserMonitoringTimingsTest < Test::Unit::TestCase

  def setup
    Time.stubs(:now).returns(2000)
    @transaction = stub(
      :transaction_name => "Name",
      :start_time => 0,
    )
  end

  def test_queue_time
    t = NewRelic::Agent::Instrumentation::BrowserMonitoringTimings.new(1000.1234, @transaction)
    assert_equal 1_000_123, t.queue_time_in_millis
  end

  def test_queue_time_clamps_to_positive
    t = NewRelic::Agent::Instrumentation::BrowserMonitoringTimings.new(-1000, @transaction)
    assert_equal 0, t.queue_time_in_millis
  end

  def test_app_time
    t = NewRelic::Agent::Instrumentation::BrowserMonitoringTimings.new(nil, @transaction)
    assert_equal 2_000_000, t.app_time_in_millis
  end

  def test_transaction_name
    t = NewRelic::Agent::Instrumentation::BrowserMonitoringTimings.new(nil, @transaction)
    assert_equal "Name", t.transaction_name
  end

  def test_defaults_to_transaction_info
    NewRelic::Agent::TransactionInfo.stubs(:get).returns(@transaction)
    t = NewRelic::Agent::Instrumentation::BrowserMonitoringTimings.new(1000)
    assert_equal "Name", t.transaction_name
  end

end
