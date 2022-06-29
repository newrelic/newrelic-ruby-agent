# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class SSLTest < Minitest::Test
  include MultiverseHelpers

  def setup
    # Similar to how jruby 1.6.8 behaves when jruby-openssl isn't installed
    Net::HTTPSession.any_instance.stubs('use_ssl=').with(true).raises(LoadError)
    Net::HTTPSession.any_instance.stubs('use_ssl=').with(false).returns(nil)
  end

  def test_agent_shuts_down_when_ssl_is_on_but_unavailable
    NewRelic::Agent.agent.expects(:shutdown).at_least_once

    run_agent(:ssl => true)
  end
end
