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
# Detection reads the runner that +Puma::Launcher#initialize+ registers, so
# installation requires the launcher to exist before the agent boots -- true
# whenever Puma itself starts the application (the +puma+ and +pumactl+
# CLIs). Entry points that load the application first and construct the
# launcher afterward (e.g. +rails server+) run detection before the runner
# exists, and the instrumentation does not install there.
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
  named :puma

  depends_on do
    defined?(Puma) && defined?(Puma::Launcher)
  end

  depends_on do
    NewRelic::Agent::Instrumentation::PumaStats.master?(
      NewRelic::Agent::Instrumentation::PumaStats.runner
    )
  end

  executes do
    NewRelic::Agent.logger.info('Installing Puma stats instrumentation')
    NewRelic::Agent::Instrumentation::PumaStats.install(
      NewRelic::Agent::Instrumentation::PumaStats.runner
    )
  end
end
