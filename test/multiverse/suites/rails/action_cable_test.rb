# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'action_cable'
if defined?(ActionCable::Channel)

require 'stringio'
require 'logger'
require 'json'

class ActionCableTest < Minitest::Test
include MultiverseHelpers

  class TestConnection
    attr_reader :transmissions, :identifiers, :logger

    def initialize
      @transmissions = []
      @identifiers = []
      @logger = Logger.new StringIO.new
    end

    def transmit data
      @transmissions << data
    end

    def last_transmission
      JSON.parse @transmissions.last
    end
  end

  class TestChannel < ActionCable::Channel::Base
    def test_action data
      transmit data['content']
    end
  end

  setup_and_teardown_agent

  def setup
    @connection = TestConnection.new
    @channel = TestChannel.new @connection, "{id: 1}"
  end

  def test_creates_trace
    @channel.perform_action({ 'action' => :test_action, 'content' => 'hello' })

    last_sample = NewRelic::Agent.instance.transaction_sampler.last_sample
    assert_equal('Controller/ActionCable/ActionCableTest::TestChannel/test_action', last_sample.transaction_name)
  end
end

end
