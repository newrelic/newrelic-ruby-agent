
class NoDnsResolv < Test::Unit::TestCase
  def test_should_no_resolve_hostname_when_agent_is_disabled
    Resolv.expects(:getaddress).never
    NewRelic::Agent.manual_start(:monitor_mode => false)
  end

  def setup
    NewRelic::Agent::Agent.instance_variable_set(:@instance, NewRelic::Agent::Agent.new)
  end

  def teardown
    $collector.reset
    NewRelic::Agent.shutdown
    NewRelic::Agent::Agent.instance_variable_set(:@instance, nil)
  end
end
