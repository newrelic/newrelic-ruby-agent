# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'fake_collector'

module MultiverseHelpers

  #
  # Agent startup/shutdown
  #
  # These are considered to be the standard steps for each test to take.
  # If your tests do something different, it's important that they clean up
  # after themselves!

  def setup_agent(opts = {})
    setup_collector

    # This will force a reconnect when we start again
    NewRelic::Agent.instance.instance_variable_set(:@connect_state, :pending)

    # Give caller a shot to setup before we start
    yield($collector) if block_given?

    NewRelic::Agent.manual_start(opts)
  end

  def teardown_agent
    reset_collector
    NewRelic::Agent.shutdown
  end

  def run_agent(options={}, &block)
    setup_agent(options)
    yield if block_given?
    teardown_agent
  end

  # Collector interactions

  def setup_collector
    $collector ||= NewRelic::FakeCollector.new
    $collector.reset
    $collector.run

    if (NewRelic::Agent.instance &&
        NewRelic::Agent.instance.service &&
        NewRelic::Agent.instance.service.collector)
      NewRelic::Agent.instance.service.collector.port = $collector.port
    end
  end

  def reset_collector
    $collector.reset
  end

  extend self
end
