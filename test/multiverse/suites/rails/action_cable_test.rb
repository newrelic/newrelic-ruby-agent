# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

begin
  require 'action_cable'
rescue LoadError
end

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

    def boom data
      raise StandardError.new("Boom!")
    end
  end

  setup_and_teardown_agent do
    @connection = TestConnection.new
    @channel = TestChannel.new @connection, "{id: 1}"
  end

  def test_creates_trace
    @channel.perform_action({ 'action' => :test_action, 'content' => 'hello' })

    last_sample = NewRelic::Agent.instance.transaction_sampler.last_sample
    assert_equal('Controller/ActionCable/ActionCableTest::TestChannel/test_action', last_sample.transaction_name)
  end

  def test_creates_web_transaction
    @channel.perform_action({ 'action'=> :test_action, 'content' => 'hello' })

    expected_metrics = {
      'HttpDispatcher' => { :call_count => 1 },
      'Controller/ActionCable/ActionCableTest::TestChannel/test_action' => { :call_count => 1}
    }

    assert_metrics_recorded expected_metrics
  end

  def test_action_with_error_is_noticed_by_agent
    @channel.perform_action({ 'action'=> :boom }) rescue nil

    error_trace = last_traced_error

    assert_equal "StandardError", error_trace.exception_class_name
    assert_equal "Boom!", error_trace.message
    assert_equal "Controller/ActionCable/ActionCableTest::TestChannel/boom", error_trace.path
  end
end

end
