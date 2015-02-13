# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), "..", "agent_helper"))

class Minitest::Test
  def after_teardown
    unfreeze_time
    super
  end
end

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
    ensure_fake_collector unless omit_collector?

    # Give caller a shot to setup before we start
    # Don't just yield, as that won't necessarily have the intended receiver
    # (the test case instance itself)
    self.instance_exec($collector, &block) if block_given? && self.respond_to?(:instance_exec)

    # It's important that this is called after the insance_exec above, so that
    # test cases have the chance to change settings on the fake collector first
    start_fake_collector unless omit_collector?

    trigger_agent_reconnect(opts)
  end

  def teardown_agent
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

  def trigger_agent_reconnect(opts={})
    # Clean-up if others don't (or we're first test after auto-loading of agent)
    if NewRelic::Agent.instance.started?
      NewRelic::Agent.shutdown
      NewRelic::Agent.logger.warn("TESTING: Agent wasn't shut down before test")
    end

    # This will force a reconnect when we start again
    NewRelic::Agent.instance.instance_variable_set(:@connect_state, :pending)

    # Almost always want a test to force a new connect when setting up
    defaults = { :sync_startup => true, :force_reconnect => true }

    NewRelic::Agent.manual_start(defaults.merge(opts))
  end

  #
  # Collector interactions
  #
  # These are here to ease interactions with the fake collector, and allow
  # classes that don't need them to avoid it by an environment variable.
  # This helps so the runner process can decide before spawning the child
  # whether we want the collector running or not.

  def ensure_fake_collector
    require 'fake_collector'
    $collector ||= NewRelic::FakeCollector.new
    $collector.reset
  end

  def start_fake_collector
    $collector.restart if $collector.needs_restart?
    agent.service.collector.port = $collector.port if agent
  end

  def omit_collector?
    ENV["NEWRELIC_OMIT_FAKE_COLLECTOR"] == "true"
  end

  extend self
end
