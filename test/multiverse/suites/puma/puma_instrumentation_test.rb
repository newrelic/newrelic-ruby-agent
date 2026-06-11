# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'json'
require 'timeout'
require 'puma'
require 'puma/configuration'
require 'puma/launcher' # defines Puma::Launcher and loads Puma::Events
require 'rack'
require 'newrelic_rpm'
require 'new_relic/agent/instrumentation/puma'

# Functional coverage that exercises the agent-managed Puma instrumentation
# against the real Puma gem (which the agent's unit-test environment does not
# load). It builds real Puma::Launchers so the master-detection gate, the
# runner lookup, and the lifecycle-event wiring run against Puma's actual
# objects rather than hand-built fixtures.
class PumaInstrumentationTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent

  PumaStats = NewRelic::Agent::Instrumentation::PumaStats

  # +setup+ is supplied by setup_and_teardown_agent; only add teardown cleanup,
  # delegating to the helper's +teardown_agent+ so the agent still shuts down.
  def teardown
    # Each test builds its own Puma::Launcher, which sets Puma's global stats
    # object. Clear it so a launcher from one test is never seen by another --
    # or by a later DependencyDetection pass -- as the active master runner.
    Puma.remove_instance_variable(:@get_stats) if Puma.instance_variable_defined?(:@get_stats)
  ensure
    teardown_agent
  end

  # --- runner lookup ---------------------------------------------------------

  def test_runner_returns_pumas_active_runner
    launcher = build_launcher

    assert_same runner_for(launcher), PumaStats.runner,
      'expected #runner to return the runner Puma stored via stats_object='
  end

  def test_runner_is_nil_when_puma_has_no_runner
    # Drop Puma's stored runner so #runner sees the absent state. Restore it
    # afterward so a later test in the same process is unaffected.
    had = Puma.instance_variable_defined?(:@get_stats)
    saved = Puma.instance_variable_get(:@get_stats) if had
    Puma.remove_instance_variable(:@get_stats) if had

    assert_nil PumaStats.runner
  ensure
    Puma.instance_variable_set(:@get_stats, saved) if had
  end

  # --- master? gate ----------------------------------------------------------

  def test_master_true_in_single_mode
    runner = runner_for(build_launcher(workers: 0))

    assert_instance_of Puma::Single, runner
    assert PumaStats.master?(runner), 'single mode should always sample'
  end

  def test_master_true_for_clustered_with_preload
    runner = runner_for(build_launcher(workers: 2, preload: :on))

    assert_instance_of Puma::Cluster, runner
    assert PumaStats.master?(runner),
      'clustered + preload loads the agent in the master, which should sample'
  end

  def test_master_false_for_clustered_without_preload
    runner = runner_for(build_launcher(workers: 2, preload: :off))

    assert_instance_of Puma::Cluster, runner
    refute PumaStats.master?(runner),
      'without preload the agent loads in a worker, which must not sample'
  end

  def test_master_true_for_clustered_with_default_preload
    # workers > 1 with no explicit setting: Puma defaults preload_app on, so the
    # agent loads in the master. Locks the default path, not just preload_app!(true).
    runner = runner_for(build_launcher(workers: 2))

    assert_instance_of Puma::Cluster, runner
    assert PumaStats.master?(runner),
      'a clustered master with default (on) preload should sample'
  end

  def test_master_false_for_single_worker_cluster_with_default_preload
    # workers == 1 defaults preload_app off (Puma's default is workers > 1), so
    # the agent loads in the lone worker and declines. Puma metrics are not
    # collected in this topology by design; this pins that contract.
    runner = runner_for(build_launcher(workers: 1))

    assert_instance_of Puma::Cluster, runner
    refute PumaStats.master?(runner),
      'a single-worker cluster defaults preload off, so the agent is in a worker'
  end

  def test_master_false_when_runner_nil
    refute PumaStats.master?(nil)
  end

  # --- stop wiring -----------------------------------------------------------

  def test_register_stop_stops_only_on_halt_restart_stop_state
    launcher = build_launcher
    spy = sampler_spy
    PumaStats.register_stop(runner_for(launcher), spy)

    %i[booting running].each { |state| launcher.events.fire(:state, state) }

    assert_equal 0, spy.stops, "non-stopping states should not stop the sampler (got #{spy.stops})"

    %i[halt restart stop].each { |state| launcher.events.fire(:state, state) }

    assert_equal 3, spy.stops, 'each of halt/restart/stop should stop the sampler'
  end

  def test_register_stop_stops_on_master_lifecycle_events
    # :state never fires on the clustered master (it is emitted by
    # Puma::Server, which the master does not instantiate), so the sampler
    # must also stop on the launcher-level lifecycle events. Puma 7+ fires
    # :before_restart / :after_stopped; Puma 6.x fires :on_restart /
    # :on_stopped. Each is asserted independently so a future refactor that
    # consolidates registrations still passes as long as the contract holds.
    %i[before_restart after_stopped on_restart on_stopped].each do |event|
      launcher = build_launcher
      spy = sampler_spy
      PumaStats.register_stop(runner_for(launcher), spy)

      launcher.events.fire(event)

      assert_operator spy.stops, :>=, 1,
        "firing #{event.inspect} should have stopped the sampler"
    end
  end

  # --- install ---------------------------------------------------------------

  def test_install_starts_sampler_on_a_background_thread_and_wires_stop
    launcher = build_launcher
    runner = runner_for(launcher)
    started = Queue.new
    spy = sampler_spy(on_start: -> { started << :started })

    returned = with_sampler_constructor_spy(spy) do
      PumaStats.install(runner)
    end

    assert_same runner, spy.constructor_arg,
      'expected install to pass the runner to PumaStatsSampler.new'
    assert_same spy, returned, 'expected install to return the sampler'
    assert_equal :started, Timeout.timeout(5) { started.pop },
      'expected install to run sampler.start on a background thread'

    # Stop wiring came along with install.
    launcher.events.fire(:state, :stop)

    assert_operator spy.stops, :>=, 1, 'expected install to register the stop handler'
  end

  def test_install_rescues_sampler_construction_failure
    runner = runner_for(build_launcher)

    result = NewRelic::Agent::PumaStatsSampler.stub(:new, ->(_) { raise 'construction failed' }) do
      PumaStats.install(runner) # must not raise
    end

    assert_nil result, 'install should swallow the failure and return nil'
  end

  # --- dependency detection --------------------------------------------------

  def test_dependency_item_installs_in_master_exactly_once
    item = DependencyDetection.dependency_by_name(:puma)
    was_executed = item&.executed

    refute_nil item, 'expected requiring the instrumentation to register a :puma dependency item'
    refute item.executed, 'precondition: item has not run (no Puma master during agent setup)'

    # A non-master process (clustered, no preload) does not satisfy the gate.
    build_launcher(workers: 2, preload: :off)

    refute_predicate item, :dependencies_satisfied?, 'must not install when not in the Puma master'

    # The Puma master (single mode here) does.
    build_launcher(workers: 0)

    assert_predicate item, :dependencies_satisfied?, 'should install in the Puma master'

    # Executing the item runs install once, with Puma's active runner...
    installed = []
    PumaStats.stub(:install, ->(runner) { installed << runner }) do
      item.execute
    end

    assert_equal 1, installed.size, 'the executes block should call install exactly once'
    assert_same PumaStats.runner, installed.first, 'install should receive the active runner'

    # ...and the item is now spent, so a later DependencyDetection pass (e.g. in
    # a forked worker that inherited this state) cannot install a second sampler.
    assert item.executed
    refute_predicate item, :dependencies_satisfied?, 'an executed item must not install again'
  ensure
    # The :puma item is a process-global singleton; restore its executed flag so
    # this test leaves it as found and no later test inherits a spent item.
    item&.instance_variable_set(:@executed, was_executed)
  end

  # --- sampler against real Puma stats ---------------------------------------

  def test_sampled_keys_are_valid_puma_stats
    # Guards against a Puma version renaming or removing a stat we sample.
    unless Puma::Server.const_defined?(:STAT_METHODS)
      skip 'Puma::Server::STAT_METHODS not defined in this Puma version'
    end

    unknown = NewRelic::Agent::PumaStatsSampler::WORKER_STAT_KEYS - Puma::Server::STAT_METHODS

    assert_empty unknown, "sampled keys missing from Puma::Server::STAT_METHODS: #{unknown.inspect}"
  end

  def test_sample_records_metrics_from_real_puma_stats
    stats_source = Struct.new(:stats).new(real_puma_server_stats)

    with_config(:'puma.start_reporting_thread_in_master' => false) do
      NewRelic::Agent::PumaStatsSampler.new(stats_source).send(:sample)
    end

    # max_threads is reported by a non-running Puma server across versions;
    # the gauge stats (running, pool_capacity, ...) only appear once the
    # thread pool is live, so we don't assert them here.
    assert_metrics_recorded('Puma/max_threads')
  end

  private

  # Builds a real Puma::Launcher, which sets Puma's stats_object to a fresh
  # runner (Puma::Single in single mode, Puma::Cluster when workers are set).
  def build_launcher(workers: 0, preload: :unset)
    conf = Puma::Configuration.new do |c|
      c.workers(workers)
      c.preload_app!(true) if preload == :on
      c.preload_app!(false) if preload == :off
    end
    pwd = Dir.pwd
    Puma::Launcher.new(conf, events: Puma::Events.new)
  ensure
    # Constructing a launcher chdirs into its restart dir (its default is the
    # cwd, so normally a no-op); restore defensively in case it isn't.
    Dir.chdir(pwd) if pwd && Dir.pwd != pwd
  end

  def runner_for(launcher)
    launcher.instance_variable_get(:@runner)
  end

  # A real Puma::Server stats hash. No sockets or threads are started, so only
  # the always-populated keys are present; this exercises our parsing against
  # Puma's actual output without booting a server.
  def real_puma_server_stats
    app = proc { |_env| [200, {}, ['OK']] }
    stats = Puma::Server.new(app).stats
    stats.is_a?(Hash) ? stats : JSON.parse(stats, symbolize_names: true)
  end

  # A stand-in sampler that counts start/stop calls and optionally runs a
  # callback on start (used to signal the background thread executed).
  def sampler_spy(on_start: nil)
    spy = Object.new
    spy.instance_variable_set(:@starts, 0)
    spy.instance_variable_set(:@stops, 0)
    spy.instance_variable_set(:@on_start, on_start)
    spy.instance_variable_set(:@constructor_arg, :unset)
    spy.define_singleton_method(:start) { @starts += 1; @on_start&.call }
    spy.define_singleton_method(:stop) { @stops += 1 }
    spy.define_singleton_method(:starts) { @starts }
    spy.define_singleton_method(:stops) { @stops }
    spy.define_singleton_method(:constructor_arg) { @constructor_arg }
    spy.define_singleton_method(:constructor_arg=) { |v| @constructor_arg = v }
    spy
  end

  # Stubs PumaStatsSampler.new to return +spy+ and records the constructor
  # argument on it, so tests can assert the runner actually reaches the sampler.
  def with_sampler_constructor_spy(spy, &blk)
    NewRelic::Agent::PumaStatsSampler.stub(:new, ->(arg) { spy.constructor_arg = arg; spy }, &blk)
  end
end
