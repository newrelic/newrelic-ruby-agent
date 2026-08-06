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
    # Disarm the late-install interceptor. Once armed it prepends itself onto
    # Puma's singleton class for the rest of the process; disarming keeps a
    # later test's build_launcher (which fires Puma.stats_object=) from
    # installing through it.
    PumaStats.instance_variable_set(:@late_install_armed, false)
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

  def test_dependency_item_is_satisfied_once_puma_is_loaded_then_spent
    item = DependencyDetection.dependency_by_name(:puma)
    was_executed = item&.executed

    refute_nil item, 'expected requiring the instrumentation to register a :puma dependency item'
    refute item.executed, 'precondition: item has not run yet (suite config disables it)'

    # The gate is "Puma is loaded and not disabled", not "in the master": the
    # runner need not exist yet (the rails server boot order), so the item is
    # satisfiable even before any launcher is built.
    with_config(:disable_puma_instrumentation => false) do
      assert_predicate item, :dependencies_satisfied?, 'should be satisfied once Puma is loaded'

      # Executing the item runs install_or_arm exactly once...
      calls = 0
      PumaStats.stub(:install_or_arm, -> { calls += 1 }) do
        item.execute
      end

      assert_equal 1, calls, 'the executes block should call install_or_arm exactly once'

      # ...and the item is now spent, so a later DependencyDetection pass (e.g.
      # in a forked worker that inherited this state) cannot run it again.
      assert item.executed
      refute_predicate item, :dependencies_satisfied?, 'an executed item must not run again'
    end
  ensure
    # The :puma item is a process-global singleton; restore its executed flag so
    # this test leaves it as found and no later test inherits a spent item.
    item&.instance_variable_set(:@executed, was_executed)
  end

  def test_dependency_item_declines_when_instrumentation_disabled
    item = DependencyDetection.dependency_by_name(:puma)

    with_config(:disable_puma_instrumentation => true) do
      refute_predicate item, :dependencies_satisfied?,
        'disable_puma_instrumentation must turn the instrumentation off'
    end
  end

  # --- install_or_arm decision -----------------------------------------------

  def test_install_or_arm_installs_in_master_when_runner_present
    runner = runner_for(build_launcher(workers: 0)) # single mode is always master

    installed = []
    PumaStats.stub(:install, ->(r) { installed << r }) do
      PumaStats.install_or_arm
    end

    assert_equal [runner], installed, 'a present master runner should install immediately'
    refute PumaStats.instance_variable_get(:@late_install_armed),
      'the eager path must not arm the late interceptor'
  end

  def test_install_or_arm_declines_when_runner_present_but_not_master
    build_launcher(workers: 2, preload: :off) # clustered worker, no preload

    installed = []
    PumaStats.stub(:install, ->(r) { installed << r }) do
      PumaStats.install_or_arm
    end

    assert_empty installed, 'a non-master runner should not install'
    refute PumaStats.instance_variable_get(:@late_install_armed),
      'a present (non-master) runner means the launcher exists, so do not arm'
  end

  def test_install_or_arm_arms_late_install_and_installs_on_registration
    # The rails server boot order: detection runs before any launcher exists.
    Puma.remove_instance_variable(:@get_stats) if Puma.instance_variable_defined?(:@get_stats)

    installed = []
    PumaStats.stub(:install, ->(r) { installed << r }) do
      PumaStats.install_or_arm

      assert_empty installed, 'arming must not install until a runner registers'
      assert PumaStats.instance_variable_get(:@late_install_armed),
        'an absent runner should arm the late interceptor'

      # A launcher registering its runner (a single-mode master here) drives the
      # prepended Puma.stats_object= interceptor, which installs exactly once.
      runner = runner_for(build_launcher(workers: 0))

      assert_equal [runner], installed, 'the stats_object= interceptor should install in the master'
      refute PumaStats.instance_variable_get(:@late_install_armed),
        'the interceptor is one-shot and disarms after the first registration'

      # A second registration (e.g. a Puma hot restart) must not start a second
      # sampler -- the one-shot disarm is the guard against that.
      build_launcher(workers: 0)

      assert_equal [runner], installed, 'a second runner registration must not reinstall'
    end
  end

  def test_late_interceptor_declines_non_master_runner_on_registration
    # The rails server boot order in a clustered/no-preload topology: the
    # launcher that registers is not a master we should sample from, so the armed
    # interceptor must decline (install_on_register routes through the master?
    # gate) while still consuming its one shot.
    Puma.remove_instance_variable(:@get_stats) if Puma.instance_variable_defined?(:@get_stats)

    installed = []
    PumaStats.stub(:install, ->(r) { installed << r }) do
      PumaStats.install_or_arm

      assert PumaStats.instance_variable_get(:@late_install_armed), 'precondition: armed'

      build_launcher(workers: 2, preload: :off) # a non-master runner registers

      assert_empty installed, 'a non-master runner registering must not install'
      refute PumaStats.instance_variable_get(:@late_install_armed),
        'the interceptor consumes its one shot even when it declines'
    end
  end

  def test_late_interceptor_isolates_agent_failure_from_puma_boot
    # The host-protection boundary: an agent-side failure inside the prepended
    # Puma.stats_object= interceptor must never escape into Puma's launcher boot.
    # super (Puma's own assignment) is left unguarded and still runs, so Puma
    # records its runner regardless; only the agent reaction is rescued.
    Puma.remove_instance_variable(:@get_stats) if Puma.instance_variable_defined?(:@get_stats)

    PumaStats.install_or_arm # arm and prepend the interceptor

    assert PumaStats.instance_variable_get(:@late_install_armed), 'precondition: armed'

    launcher = nil
    PumaStats.stub(:install_on_register, ->(_) { raise 'agent reaction blew up' }) do
      launcher = build_launcher(workers: 0) # fires Puma.stats_object=; must not raise
    end

    assert_same runner_for(launcher), Puma.instance_variable_get(:@get_stats),
      'super must still run so Puma records its runner despite the agent failure'
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

    NewRelic::Agent::PumaStatsSampler.new(stats_source).send(:sample)

    # max_threads is reported by a non-running Puma server across versions;
    # the gauge stats (running, pool_capacity, ...) only appear once the
    # thread pool is live, so we don't assert them here.
    assert_metrics_recorded('Ruby/Puma/max_threads')
  end

  private

  # Builds a real Puma::Launcher, which sets Puma's stats_object to a fresh
  # runner (Puma::Single in single mode, Puma::Cluster when workers are set).
  #
  # Workers are passed through Puma's user options (the +-w+ CLI path), not the
  # config block. Puma derives the +preload_app+ default from the worker count,
  # and on Puma 6.x it does so during Configuration construction -- before the
  # config block runs -- so block-set workers stay at the workers-0 default
  # (preload off). (Puma 8.x recomputes it later, from the launcher, and is
  # unaffected.) User options are in place before either version's computation,
  # so this reproduces the default-preload-on behavior +-w 2+ yields in a real
  # deployment across every supported Puma version.
  def build_launcher(workers: 0, preload: :unset)
    conf = Puma::Configuration.new(workers: workers) do |c|
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
