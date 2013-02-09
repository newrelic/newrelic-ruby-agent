class SSLTest < Test::Unit::TestCase

  def setup
    # This is similar to how jruby 1.6.8 behaves when jruby-openssl isn't
    # installed
    @original_ssl_config = NewRelic::Agent.config[:ssl]
    NewRelic::Agent.config.apply_config(:ssl => true)
    Net::HTTPSession.any_instance.stubs('use_ssl=').raises(LoadError)
  end

  def teardown
    NewRelic::Agent.config.apply_config(:ssl => @original_ssl_config)
  end

  def test_agent_shuts_down_when_ssl_is_on_but_unavailable
    ::NewRelic::Agent.agent.expects(:shutdown)
    ::NewRelic::Agent.agent.service.expects(:send_request).never
    ::NewRelic::Agent.agent.service.http_connection
  ensure
  end
end
