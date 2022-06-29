# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'socket'

class ServiceTimeoutTest < Minitest::Test
  def setup
    hk = TCPServer.new('127.0.0.1', 0)
    @port = hk.addr[1]

    Thread.new {
      client = hk.accept
      client.gets
      sleep 4
      client.close
      Thread.exit
    }
  end

  def teardown
    NewRelic::Agent.config.reset_to_defaults
  end

  def test_service_timeout
    server = NewRelic::Control::Server.new('localhost', @port)
    NewRelic::Agent.config.add_config_for_testing(:timeout => 0.1)

    service = NewRelic::Agent::NewRelicService.new('deadbeef', server)

    assert_raises NewRelic::Agent::ServerConnectionException do
      service.send(:send_request,
        :uri => '/agent_listener/8/bd0e1d52adade840f7ca727d29a86249e89a6f1c/preconnect',
        :encoding => 'UTF-8', :collector => server, :data => 'blah')
    end
  end
end
