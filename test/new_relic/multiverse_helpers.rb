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
    make_sure_agent_reconnects(opts)

    # Give caller a shot to setup before we start
    yield($collector) if block_given?

    NewRelic::Agent.manual_start(opts)
  end

  def teardown_agent
    reset_collector

    # Put the configs back where they belong....
    NewRelic::Agent.config.reset_to_defaults

    # Renaming rules don't get cleared on connect--only appended to
    NewRelic::Agent.instance.transaction_rules.rules.clear
    NewRelic::Agent.instance.metric_rules.rules.clear

    # Clear out lingering stats we didn't transmit
    NewRelic::Agent.instance.reset_stats

    NewRelic::Agent.shutdown
  end

  def run_agent(options={}, &block)
    setup_agent(options)
    yield if block_given?
    teardown_agent
  end

  def make_sure_agent_reconnects(opts)
    # Clean-up if others don't (or we're first test after auto-loading of agent)
    if NewRelic::Agent.instance.started?
      NewRelic::Agent.shutdown
      NewRelic::Agent.logger.warn("TESTING: Agent wasn't shut down before test")
    end

    # This will force a reconnect when we start again
    NewRelic::Agent.instance.instance_variable_set(:@connect_state, :pending)

    # Almost always want a test to force a new connect when setting up
    default_options(opts,
                    :sync_startup => true,
                    :force_reconnect => true)
  end

  def default_options(options, defaults={})
    defaults.each do |(k, v)|
      options.merge!({k => v}) unless options.key?(k)
    end
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
