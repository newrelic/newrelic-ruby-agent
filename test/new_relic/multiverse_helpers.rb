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

    # If a test not using the multiverse helper runs before us, we might need
    # to clean up before a test too.
    NewRelic::Agent.drop_buffered_data

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

  def run_harvest
    NewRelic::Agent.instance.send(:transmit_data)
    NewRelic::Agent.instance.send(:transmit_event_data)
  end

  def single_transaction_trace_posted
    posts = $collector.calls_for("transaction_sample_data")
    assert_equal 1, posts.length, "Unexpected post count"

    transactions = posts.first.samples
    assert_equal 1, transactions.length, "Unexpected trace count"

    transactions.first
  end

  def single_error_posted
    assert_equal 1, $collector.calls_for("error_data").length
    assert_equal 1, $collector.calls_for("error_data").first.errors.length

    $collector.calls_for("error_data").first.errors.first
  end

  def single_event_posted
    assert_equal 1, $collector.calls_for("analytic_event_data").length
    assert_equal 1, $collector.calls_for("analytic_event_data").first.events.length

    $collector.calls_for("analytic_event_data").first.events.first
  end

  def single_metrics_post
    assert_equal 1, $collector.calls_for("metric_data").length

    $collector.calls_for("metric_data").first
  end

  def single_connect_posted
    assert_equal 1, $collector.calls_for(:connect).size
    $collector.calls_for(:connect).first
  end

  def capture_js_data
    state = NewRelic::Agent::TransactionState.tl_get
    events = stub(:subscribe => nil)
    @instrumentor = NewRelic::Agent::JavascriptInstrumentor.new(events)
    @js_data = @instrumentor.data_for_js_agent(state)

    raw_attributes = @js_data["atts"]

    if raw_attributes
      attributes = NewRelic::JSONWrapper.load @instrumentor.obfuscator.deobfuscate(raw_attributes)
      @js_custom_attributes = attributes['u']
      @js_agent_attributes = attributes['a']
    end
  end

  def assert_transaction_trace_has_agent_attribute(attribute, expected)
    actual = single_transaction_trace_posted.agent_attributes[attribute]
    assert_equal expected, actual
  end

  def assert_event_has_agent_attribute(attribute, expected)
    assert_equal expected, single_event_posted.last[attribute]
  end

  def assert_error_has_agent_attribute(attribute, expected)
    assert_equal expected, single_error_posted.params["agentAttributes"][attribute]
  end

  def assert_transaction_tracer_has_custom_attributes(attribute, expected)
    actual = single_transaction_trace_posted.custom_attributes[attribute]
    assert_equal expected, actual
  end

  def assert_transaction_event_has_custom_attributes(attribute, expected)
    assert_equal expected, single_event_posted[1][attribute]
  end

  def assert_error_collector_has_custom_attributes(attribute, expected)
    assert_equal expected, single_error_posted.params["userAttributes"][attribute]
  end

  def assert_browser_monitoring_has_custom_attributes(attribute, expected)
    assert_equal expected, @js_custom_attributes[attribute]
  end

  def assert_browser_monitoring_has_agent_attribute(attribute, expected)
    assert_equal expected, @js_agent_attributes[attribute]
  end

  def refute_transaction_tracer_has_custom_attributes(attribute)
    refute_includes single_transaction_trace_posted.custom_attributes, attribute
  end

  def refute_transaction_event_has_custom_attributes(attribute)
    refute_includes single_event_posted[1], attribute
  end

  def refute_error_collector_has_custom_attributes(attribute)
    refute_includes single_error_posted.params["userAttributes"], attribute
  end

  def refute_browser_monitoring_has_custom_attributes(_)
    assert_nil @js_custom_attributes
  end

  def refute_transaction_trace_has_agent_attribute(attribute)
    refute_includes single_transaction_trace_posted.agent_attributes, attribute
  end

  def refute_event_has_agent_attribute(attribute)
    refute_includes single_event_posted.last, attribute
  end

  def refute_error_has_agent_attribute(attribute)
    refute_includes single_error_posted.params["agentAttributes"], attribute
  end

  def refute_browser_monitoring_has_any_attributes
    refute_includes @js_data, "atts"
  end

  def refute_browser_monitoring_has_agent_attribute(_)
    assert_nil @js_agent_attributes
  end

  def refute_event_has_attribute(key)
    evt = single_event_posted
    refute_includes evt[0], key, "Found unexpected attribute #{key} in txn event intrinsics"
    refute_includes evt[1], key, "Found unexpected attribute #{key} in txn event custom attributes"
    refute_includes evt[2], key, "Found unexpected attribute #{key} in txn event agent attributes"
  end

  def attributes_for_single_error_posted(key)
    run_harvest
    single_error_posted.params[key]
  end

  def user_attributes_for_single_error_posted
    attributes_for_single_error_posted("userAttributes")
  end

  def agent_attributes_for_single_error_posted
    attributes_for_single_error_posted("agentAttributes")
  end

  def agent_attributes_for_single_event_posted
    run_harvest
    single_event_posted[2]
  end

  def agent_attributes_for_single_event_posted_without_ignored_attributes
    ignored_keys = ["httpResponseCode", "request.headers.referer",
      "request.parameters.controller", "request.parameters.action"]
    attrs = agent_attributes_for_single_event_posted
    ignored_keys.each { |k| attrs.delete(k) }
    attrs
  end

  extend self
end
