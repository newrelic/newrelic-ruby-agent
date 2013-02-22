# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class SSLTest < Test::Unit::TestCase

  def setup
    # This is similar to how jruby 1.6.8 behaves when jruby-openssl isn't
    # installed
    @original_ssl_config = NewRelic::Agent.config[:ssl]
    NewRelic::Agent.config.apply_config(:ssl => true)
    NewRelic::Agent.agent = NewRelic::Agent::Agent.new
    Net::HTTPSession.any_instance.stubs('use_ssl=').raises(LoadError)
  end

  def teardown
    NewRelic::Agent.config.apply_config(:ssl => @original_ssl_config)
  end

  def test_agent_shuts_down_when_ssl_is_on_but_unavailable
    ::NewRelic::Agent.agent.expects(:shutdown)
    ::NewRelic::Agent.expects(:finish_setup).never
    ::NewRelic::Agent.agent.connect_in_foreground
  ensure
  end
end
