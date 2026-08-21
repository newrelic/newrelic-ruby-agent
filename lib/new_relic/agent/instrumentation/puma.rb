# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'new_relic/agent/puma_stats_sampler'

module NewRelic
  module Agent
    module Instrumentation
      module PumaStats
        module_function

        # Puma stores the runner via +Puma.stats_object=+. No public accessor,
        # so read the ivar that the setter writes.
        def runner # :nodoc:
          return nil unless defined?(::Puma) && ::Puma.instance_variable_defined?(:@get_stats)

          ::Puma.instance_variable_get(:@get_stats)
        end

        # True only where the agent should sample: single mode (one process) or
        # clustered with +preload_app!+ (where the agent is loaded in the master process).
        def master?(runner) # :nodoc:
          return false if runner.nil?
          return true if defined?(::Puma::Single) && runner.is_a?(::Puma::Single)
          return false unless runner.respond_to?(:options)

          !!runner.options[:preload_app]
        end

        def install_or_arm # :nodoc:
          current = runner
          current ? install_in_master(current) : arm_late_install
        end

        def install_in_master(runner) # :nodoc:
          unless master?(runner)
            log_puma_6x_preload_warning(runner)
            return
          end

          NewRelic::Agent.logger.info('Installing Puma stats instrumentation')
          install(runner)
        end

        # Puma 6.x doesn't apply +preload_app+ defaults from the config block,
        # so a clustered 6.x app with +workers 2+ but no explicit +preload_app!(true)+
        # silently gets no metrics.
        def log_puma_6x_preload_warning(runner) # :nodoc:
          return unless runner&.respond_to?(:options)
          return unless runner.options[:workers].to_i > 1 && !runner.options[:preload_app]
          return unless defined?(::Puma::Const::VERSION) && ::Puma::Const::VERSION.start_with?('6.')

          NewRelic::Agent.logger.warn(
            'Did not install Puma instrumentation. Set preload_app!(true) explicitly in your puma.rb to enable Puma metrics.'
          )
        end

        # Prepends a one-shot interceptor on +Puma.stats_object=+ so the agent
        # installs when the launcher registers its runner (+rails server+ boot
        # order). The prepend is permanent, so +@late_install_armed+ does the real
        # gating: disarming it on the first registration keeps a Puma hot restart
        # from starting a second sampler.
        def arm_late_install # :nodoc:
          @late_install_armed = true
          ::Puma.singleton_class.prepend(StatsObjectRegistration)
        end

        # Invoked by the interceptor when Puma registers a runner. One-shot:
        # disarm before installing so the registration is handled exactly once.
        def install_on_register(runner) # :nodoc:
          return unless @late_install_armed

          @late_install_armed = false
          install_in_master(runner)
        end

        # Intercepts +Puma.stats_object=+ to install when a launcher registers
        # its runner. +super+ runs Puma's own assignment unguarded; only the
        # agent reaction is rescued, so an agent-side failure cannot escape
        # into Puma's launcher boot.
        module StatsObjectRegistration # :nodoc:
          def stats_object=(runner)
            super
            begin
              NewRelic::Agent::Instrumentation::PumaStats.install_on_register(runner)
            rescue => e
              NewRelic::Agent.logger.error('Error installing New Relic Puma stats instrumentation on runner registration', e)
            end
          end
        end

        # Started in the master before workers fork, so forked workers do not
        # inherit the sampling thread.
        def install(runner) # :nodoc:
          sampler = NewRelic::Agent::PumaStatsSampler.new(runner)
          register_stop(runner, sampler)
          Thread.new { sampler.start }
          sampler
        rescue => e
          NewRelic::Agent.logger.error('Failed to start the New Relic Puma stats sampler', e)
          nil
        end

        # Stops the sampler on Puma shutdown/restart. Registers both Puma 7+
        # events (+:before_restart+/+:after_stopped+) and Puma 6.x events
        # (+:on_restart+/+:on_stopped+), plus +:state+ for single mode (the
        # clustered master runs no +Puma::Server+). +stop+ is idempotent, so
        # overlapping events are harmless.
        def register_stop(runner, sampler) # :nodoc:
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
  @name = :puma

  depends_on do
  defined?(Puma) && (defined?(Puma::Launcher) || defined?(Puma::RackHandler)) &&
    (defined?(Puma::Const) || require('puma/const')) &&
    NewRelic::Helper.version_satisfied?(Puma::Const::VERSION, '>=', '6.6.0') &&
    !NewRelic::Agent.config[:disable_puma_instrumentation]
  end

  executes do
    NewRelic::Agent::Instrumentation::PumaStats.install_or_arm
  end
end
