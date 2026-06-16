# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'new_relic/agent/puma_stats_sampler'

# Agent-managed Puma server-statistics instrumentation.
#
# Puma exposes cluster-wide statistics only from its master process. When an
# application runs with +preload_app!+ the agent is loaded in the master during
# app preload, so this instrumentation installs there and samples the master's
# stats on a background thread. Without +preload_app!+ the agent loads in each
# worker instead of the master, where +#master?+ correctly declines so the
# instrumentation no-ops. Single mode is one process and always samples.
#
# Detection reads the runner that +Puma::Launcher#initialize+ registers. When
# Puma itself starts the application (the +puma+ and +pumactl+ CLIs) the runner
# already exists at boot, so the instrumentation installs immediately. Entry
# points that load the application first and construct the launcher afterward
# (e.g. +rails server+) run detection before the runner exists; for those the
# agent arms a one-shot interceptor on +Puma.stats_object=+ -- the setter the
# launcher calls when it registers its runner -- so installation happens through
# the same +#master?+ gate the instant the launcher appears.
module NewRelic
  module Agent
    module Instrumentation
      module PumaStats
        module_function

        # Puma stores the active runner (Puma::Cluster or Puma::Single) on the
        # +Puma+ module when the launcher is constructed -- it is the only handle
        # to the master's cluster-wide stats and lifecycle. Puma exposes the
        # runner's *stats* publicly (+Puma.stats_hash+) but not the runner
        # object, so reach it through the ivar the +stats_object=+ setter writes.
        def runner
          return nil unless defined?(::Puma) && ::Puma.instance_variable_defined?(:@get_stats)

          ::Puma.instance_variable_get(:@get_stats)
        end

        # True only where the agent should sample: single mode (one process), or
        # clustered mode with +preload_app!+ (the configuration where the agent
        # is present in the master). In a non-preload deployment this runs in a
        # worker, where +preload_app+ is false, so it declines.
        def master?(runner)
          return false if runner.nil?
          return true if defined?(::Puma::Single) && runner.is_a?(::Puma::Single)
          return false unless runner.respond_to?(:options)

          !!runner.options[:preload_app]
        end

        # Runs at dependency-detection time. If Puma has already registered its
        # runner (the +puma+/+pumactl+ boot order), install in the master right
        # away. Otherwise the launcher does not exist yet (the +rails server+
        # boot order), so arm the late interceptor instead and let it install
        # when the runner registers.
        def install_or_arm
          current = runner
          current ? install_in_master(current) : arm_late_install
        end

        # Installs the sampler when +runner+ is the master we should sample from,
        # and declines otherwise. Shared by the eager detection path and the
        # late +Puma.stats_object=+ interceptor.
        def install_in_master(runner)
          return unless master?(runner)

          NewRelic::Agent.logger.info('Installing Puma stats instrumentation')
          install(runner)
        end

        # Prepends a one-shot interceptor on +Puma.stats_object=+ so the agent
        # installs when a launcher registers its runner after detection already
        # ran (the +rails server+ boot order). Prepending is idempotent, but the
        # +@late_install_armed+ flag is the real gate: the interceptor only acts
        # while armed and disarms itself on the first registration, so a later
        # +stats_object=+ (e.g. a Puma hot restart) cannot start a second
        # sampler, and an unarmed eager-path process is unaffected.
        def arm_late_install
          @late_install_armed = true
          ::Puma.singleton_class.prepend(StatsObjectRegistration)
        end

        # Invoked by the interceptor when Puma registers a runner. One-shot:
        # disarm before installing so the registration is handled exactly once.
        def install_on_register(runner)
          return unless @late_install_armed

          @late_install_armed = false
          install_in_master(runner)
        end

        # Intercepts +Puma.stats_object=+, the setter +Puma::Launcher#initialize+
        # calls to publish its runner. Prepended onto Puma's singleton class so
        # +super+ performs Puma's own assignment before the agent reacts.
        #
        # The agent reaction runs inside Puma's launcher boot here, so it is
        # wrapped so an agent-side failure can never escape into +stats_object=+
        # and break Puma. (+super+ is left unguarded -- a failure there is Puma's
        # own and must propagate.) This restores for the late path the error
        # isolation the eager path gets for free from +DependencyDetection#execute+.
        module StatsObjectRegistration
          def stats_object=(runner)
            super
            begin
              NewRelic::Agent::Instrumentation::PumaStats.install_on_register(runner)
            rescue => e
              NewRelic::Agent.logger.error('Error installing New Relic Puma stats instrumentation on runner registration', e)
            end
          end
        end

        # Builds the sampler, registers a stop on Puma's lifecycle events, and
        # runs the sampling loop on a background thread. Started in the master
        # before workers fork, so forked workers do not inherit the thread.
        def install(runner)
          sampler = NewRelic::Agent::PumaStatsSampler.new(runner)
          register_stop(runner, sampler)
          Thread.new { sampler.start }
          sampler
        rescue => e
          NewRelic::Agent.logger.error('Failed to start the New Relic Puma stats sampler', e)
          nil
        end

        # Stops the sampler thread on Puma shutdown/restart. The runner does not
        # expose its launcher (or the launcher's lifecycle events) publicly, so
        # reach them through the +@launcher+ ivar. The launcher fires
        # +:before_restart+/+:after_stopped+ (Puma 7+) or +:on_restart+/
        # +:on_stopped+ (Puma 6.x); +Puma::Server+ separately fires
        # +:state+ with +:stop+/+:halt+/+:restart+, the only shutdown signal in
        # single mode (the clustered master runs no server, so it never fires
        # +:state+). +stop+ is idempotent, so overlapping events for one
        # shutdown are harmless.
        def register_stop(runner, sampler)
          launcher = runner.instance_variable_get(:@launcher)
          return unless launcher.respond_to?(:events)

          events = launcher.events
          events.register(:state) { |state| sampler.stop if %i[halt restart stop].include?(state) }
          %i[before_restart after_stopped on_restart on_stopped].each do |event|
            events.register(event) { sampler.stop }
          end
        end
      end
    end
  end
end

DependencyDetection.defer do
  # Set +@name+ directly, as +sequel+ does, rather than calling +named+. The two
  # are equivalent at runtime, but the orphan-config test treats a +named+ entry
  # as a promise that +disable_<name>+ / +instrumentation.<name>+ config keys
  # exist. This instrumentation defines neither; it gates on a dedicated
  # +disable_puma_instrumentation+ via the explicit +depends_on+ below.
  @name = :puma

  depends_on do
    defined?(Puma) && defined?(Puma::Launcher)
  end

  depends_on do
    !NewRelic::Agent.config[:disable_puma_instrumentation]
  end

  # No +master?+ gate here: in the +rails server+ boot order the runner does
  # not exist yet at detection time. install_or_arm installs in the master when
  # the runner is already present and otherwise arms the late interceptor.
  executes do
    NewRelic::Agent::Instrumentation::PumaStats.install_or_arm
  end
end
