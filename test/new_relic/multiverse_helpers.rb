# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), "..", "agent_helper"))

module MultiverseHelpers

  #
  # Agent startup/shutdown
  #
  # These are considered to be the standard steps for each test to take.
  # If your tests do something different, it's important that they clean up
  # after themselves!

  def self.included(base)
    base.extend(self)
  end

  def agent
    NewRelic::Agent.instance
  end

  def setup_and_teardown_agent(opts = {}, &block)
    define_method(:setup) do
      setup_agent(opts, &block)
    end

    define_method(:teardown) do
      teardown_agent
    end
  end

  def setup_agent(opts = {}, &block)
    setup_collector
    make_sure_agent_reconnects(opts)

    # Give caller a shot to setup before we start
    # Don't just yield, as that won't necessary have the intended receiver
    # (the test case instance itself)
    self.instance_exec($collector, &block) if block_given? && self.respond_to?(:instance_exec)

    NewRelic::Agent.manual_start(opts)
  end

  def teardown_agent
    reset_collector

    # Put the configs back where they belong....
    NewRelic::Agent.config.reset_to_defaults

    # Renaming rules don't get cleared on connect--only appended to
    NewRelic::Agent.instance.transaction_rules.clear
    NewRelic::Agent.instance.stats_engine.metric_rules.clear

    # Clear out lingering stats we didn't transmit
    NewRelic::Agent.drop_buffered_data

    # Clear the error collector's ignore_filter
    NewRelic::Agent.instance.error_collector.instance_variable_set(:@ignore_filter, nil)

    # Clean up any thread-local variables starting with 'newrelic'
    NewRelic::Agent::TransactionState.tl_clear_for_testing

    NewRelic::Agent.instance.transaction_sampler.reset!

    NewRelic::Agent.shutdown

    # If we didn't start up right, our Control might not have reset on shutdown
    NewRelic::Control.reset
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

  #
  # Collector interactions
  #
  # These are here to ease interactions with the fake collector, and allow
  # classes that don't need them to avoid it by an environment variable.
  # This helps so the runner process can decide before spawning the child
  # whether we want the collector running or not.

  def setup_collector
    return if omit_collector?

    require 'fake_collector'
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
    return if omit_collector?
    $collector.reset
  end

  def omit_collector?
    ENV["NEWRELIC_OMIT_FAKE_COLLECTOR"] == "true"
  end

  extend self
end
