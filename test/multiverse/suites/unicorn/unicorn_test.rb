# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'logger'
require 'unicorn'
require 'newrelic_rpm'
require 'rack'

class UnicornTest < Minitest::Test
  include MultiverseHelpers
  attr_accessor :server

  def setup
    NewRelic::Agent.stubs(:logger).returns(NewRelic::Agent::MemoryLogger.new)
    @server = ::Unicorn::HttpServer.new(
      ::Rack::Builder.app(
        lambda { [200, {'Content-Type' => 'text/html'}, ['OK']] }
      )
    )
    @server.start
    trigger_agent_reconnect
  end

  def teardown
    @server.stop
    File.unlink('log/newrelic_agent.log')
  end

  def test_unicorn_set_as_discovered_dispatcher
    assert_logged('Dispatcher: unicorn')
  end

  def test_defer_message_logged_when_unicorn_in_use
    assert_logged('Deferring startup of agent reporting thread because unicorn may fork.')
  end

  def assert_logged(expected)
    logger = NewRelic::Agent.logger

    flattened = logger.messages.flatten
    found = flattened.any? { |msg| msg.to_s.include?(expected) }
    assert(found, "Didn't see message '#{expected}'")
  end
end
