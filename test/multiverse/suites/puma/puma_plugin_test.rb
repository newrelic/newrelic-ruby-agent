# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'json'
require 'puma'
require 'puma/plugin' # defines Puma::Plugins
require 'rack'
require 'newrelic_rpm'
require 'new_relic/agent/puma_stats_sampler'

# Functional coverage that exercises the Puma plugin against the real Puma gem
# (which the agent's unit-test environment does not load): plugin registration
# through Puma's loader, and the sampler working against Puma's actual stats
# rather than a hand-built fixture.
class PumaPluginTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent

  def test_plugin_registers_with_puma
    # Puma::Plugins.find requires "puma/plugin/newrelic" and returns the class
    # registered by Puma::Plugin.create, so this asserts our file integrates
    # with Puma's plugin loader.
    assert Puma::Plugins.find('newrelic'),
      'expected `plugin "newrelic"` to be resolvable by Puma'
  end

  def test_sampled_keys_are_valid_puma_stats
    # Guards against a Puma version renaming or removing a stat we sample.
    unless Puma::Server.const_defined?(:STAT_METHODS)
      skip 'Puma::Server::STAT_METHODS not defined in this Puma version'
    end

    unknown = NewRelic::Agent::PumaStatsSampler::WORKER_STAT_KEYS - Puma::Server::STAT_METHODS

    assert_empty unknown, "sampled keys missing from Puma::Server::STAT_METHODS: #{unknown.inspect}"
  end

  def test_sample_records_metrics_from_real_puma_stats
    launcher = Struct.new(:stats).new(real_puma_server_stats)

    with_config(:'puma.start_reporting_thread_in_master' => false) do
      NewRelic::Agent::PumaStatsSampler.new(launcher).send(:sample)
    end

    # max_threads is reported by a non-running Puma server across versions;
    # the gauge stats (running, pool_capacity, ...) only appear once the
    # thread pool is live, so we don't assert them here.
    assert_metrics_recorded('Puma/max_threads')
  end

  # --- plugin start: lifecycle hookup ----------------------------------------

  def test_plugin_starts_sampler_in_background
    spy = sampler_spy
    captured = nil
    launcher = fake_launcher
    plugin = plugin_with_captured_in_background(proc { |blk| captured = blk })

    with_sampler_constructor_spy(spy) do
      plugin.start(launcher)
    end

    assert_same launcher, spy.constructor_arg,
      'expected the plugin to pass its launcher to PumaStatsSampler.new'
    refute_nil captured, 'expected plugin to register a sampler.start block via in_background'
    captured.call

    assert_equal 1, spy.starts, 'expected sampler.start to be called from the in_background block'
  end

  def test_plugin_state_event_stops_sampler_only_on_halt_restart_stop
    spy = sampler_spy
    launcher = fake_launcher
    plugin = plugin_with_captured_in_background(proc { |_blk| })

    with_sampler_constructor_spy(spy) do
      plugin.start(launcher)
    end

    %i[booting running].each { |state| launcher.events.fire(:state, state) }

    assert_equal 0, spy.stops, "non-stopping states should not call sampler.stop (got #{spy.stops})"

    %i[halt restart stop].each { |state| launcher.events.fire(:state, state) }

    assert_equal 3, spy.stops, 'each of halt/restart/stop should call sampler.stop'
  end

  def test_plugin_master_lifecycle_events_stop_sampler
    # :state never fires on the clustered-mode master (it is emitted by
    # Puma::Server, which the master does not instantiate), so the sampler
    # must also stop on the launcher-level lifecycle events. Puma 7+ fires
    # :before_restart / :after_stopped; Puma 6.x fires :on_restart /
    # :on_stopped (the names were renamed in 7.0). Each event is asserted
    # independently so a future refactor that consolidates registrations
    # (e.g. via .uniq or a per-shutdown guard) still passes as long as the
    # actual contract -- "this event triggers stop" -- holds.
    [:before_restart, :after_stopped, :on_restart, :on_stopped].each do |event|
      spy = sampler_spy
      launcher = fake_launcher
      plugin = plugin_with_captured_in_background(proc { |_blk| })

      with_sampler_constructor_spy(spy) do
        plugin.start(launcher)
      end

      launcher.events.fire(event)

      assert_operator spy.stops, :>=, 1,
        "firing #{event.inspect} should have triggered at least one sampler.stop"
    end
  end

  def test_plugin_rescues_sampler_construction_failure
    # Top-level rescue must keep an internal failure from crashing Puma boot.
    launcher = fake_launcher
    plugin = plugin_with_captured_in_background(proc { |_blk| })

    NewRelic::Agent::PumaStatsSampler.stub(:new, ->(_) { raise 'construction failed' }) do
      plugin.start(launcher) # must not raise
    end

    assert(launcher.log_writer.lines.any? { |l| l.include?('failed to start') },
      "expected a failure log line, got: #{launcher.log_writer.lines.inspect}")
  end

  def test_plugin_skips_when_newrelic_rpm_not_loaded
    # The guard at the top of start uses respond_to?(:config) to detect
    # whether the agent itself is loaded (the bare `module NewRelic; module
    # Agent` in puma_stats_sampler.rb defines the constant unconditionally).
    launcher = fake_launcher
    plugin = plugin_with_captured_in_background(proc { |_blk| flunk('in_background must not run when rpm is absent') })

    # Use a splat for the optional include_private second arg so Ruby
    # internals that call respond_to?(name, true) don't trip ArgumentError.
    NewRelic::Agent.stub(:respond_to?, ->(name, *) { name != :config }) do
      plugin.start(launcher)
    end

    assert(launcher.log_writer.lines.any? { |l| l.include?('newrelic_rpm is not loaded') },
      "expected a 'not loaded' log line, got: #{launcher.log_writer.lines.inspect}")
  end

  private

  # A real Puma::Server stats hash. No sockets or threads are started, so only
  # the always-populated keys are present; this exercises our parsing against
  # Puma's actual output without booting a server.
  def real_puma_server_stats
    app = proc { |_env| [200, {}, ['OK']] }
    stats = Puma::Server.new(app).stats
    stats.is_a?(Hash) ? stats : JSON.parse(stats, symbolize_names: true)
  end

  # Captures #log calls so tests can assert against them without writing to
  # stdout/stderr; otherwise behaves like Puma::LogWriter.
  class CapturingLogWriter
    attr_reader :lines

    def initialize
      @lines = []
    end

    def log(str)
      @lines << str.to_s
    end
  end

  def fake_launcher
    Struct.new(:events, :log_writer).new(Puma::Events.new, CapturingLogWriter.new)
  end

  # Replaces +in_background+ on a fresh plugin instance so the supplied
  # +on_block+ proc decides when (or whether) to invoke the sampler block.
  # +yield+ can't be used here because the singleton method block has its
  # own implicit block argument (the one Puma's API passes in), so the
  # capture is intentionally an explicit Proc.
  def plugin_with_captured_in_background(on_block)
    plugin = Puma::Plugins.find('newrelic').new
    plugin.define_singleton_method(:in_background) { |&blk| on_block.call(blk) }
    plugin
  end

  # Builds a spy that records (a) what the plugin instantiated the sampler
  # with and (b) start/stop call counts. Exposing +constructor_arg+ lets
  # tests assert the launcher actually reaches PumaStatsSampler.new, which a
  # bare +stub(:new, spy)+ would silently miss.
  def sampler_spy
    spy = Object.new
    spy.instance_variable_set(:@starts, 0)
    spy.instance_variable_set(:@stops, 0)
    spy.instance_variable_set(:@constructor_arg, :unset)
    spy.define_singleton_method(:start) { @starts += 1 }
    spy.define_singleton_method(:stop) { @stops += 1 }
    spy.define_singleton_method(:starts) { @starts }
    spy.define_singleton_method(:stops) { @stops }
    spy.define_singleton_method(:constructor_arg) { @constructor_arg }
    spy.define_singleton_method(:constructor_arg=) { |v| @constructor_arg = v }
    spy
  end

  # Wraps PumaStatsSampler.new with a stub that returns +spy+ and records
  # the constructor argument on it. Use in place of a bare
  # `NewRelic::Agent::PumaStatsSampler.stub(:new, spy) do ... end`.
  def with_sampler_constructor_spy(spy, &blk)
    NewRelic::Agent::PumaStatsSampler.stub(:new, ->(launcher) { spy.constructor_arg = launcher; spy }, &blk)
  end
end
