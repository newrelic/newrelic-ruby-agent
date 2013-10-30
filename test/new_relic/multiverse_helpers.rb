# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

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
      before_setup if respond_to?(:before_setup)
      setup_agent(opts, &block)
      after_setup if respond_to?(:after_setup)
    end

    define_method(:teardown) do
      before_teardown if respond_to?(:before_teardown)
      teardown_agent
      after_teardown if respond_to?(:after_teardown)
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
    NewRelic::Agent.instance.transaction_rules.rules.clear
    NewRelic::Agent.instance.stats_engine.metric_rules.rules.clear

    # Clear out lingering stats we didn't transmit
    NewRelic::Agent.instance.reset_stats

    # Clear out lingering errors in the collector
    NewRelic::Agent.instance.error_collector.harvest_errors
    NewRelic::Agent.instance.error_collector.instance_variable_set(:@ignore_filter, nil)

    # Clean up any thread-local variables starting with 'newrelic'
    Thread.current.keys.select { |k| k.to_s =~ /^newrelic/i }.each do |key|
      Thread.current[key] = nil
    end

    NewRelic::Agent.instance.transaction_sampler.reset!

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

if RUBY_VERSION < "1.8.7"
  # No instance_exec in 1.8.6... sigh
  #
  # Cribbed from https://www.ruby-forum.com/topic/72172#101957, most straight
  # forward implementation I could find without using ActiveSupport
  class Object
    unless defined? instance_exec # 1.9
      def instance_exec(*arguments, &block)
        block.bind(self)[*arguments]
      end
    end
  end

  class Proc
    def bind(object)
      block, time = self, Time.now
      (class << object; self end).class_eval do
        method_name = "__bind_#{time.to_i}_#{time.usec}"
        define_method(method_name, &block)
        method = instance_method(method_name)
        remove_method(method_name)
        method
      end.bind(object)
    end
  end
end
