# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'puma/plugin'
require 'new_relic/agent/puma_stats_sampler'

# New Relic Puma plugin.
#
# Reports Puma's server statistics to New Relic as +Puma/*+ timeslice
# metrics: thread-pool +backlog+, +running+ threads,
# +spare_thread_capacity+, +max_threads+, and +requests_count+ in every
# mode; +workers+ count additionally in clustered mode.
#
# Enable it by adding the following to your +config/puma.rb+:
#
#     plugin 'newrelic'
#
# The sampling runs in the Puma master process and is safe to use under New
# Relic High Security Mode. See
# +lib/new_relic/agent/puma_stats_sampler.rb+ for the rationale and the
# +puma.*+ configuration options.
Puma::Plugin.create do
  def start(launcher)
    # +require 'new_relic/agent/puma_stats_sampler'+ at the top of this file
    # opens +module NewRelic; module Agent+, so the constant always exists
    # once this plugin loads. Check for a real agent API to detect whether
    # +newrelic_rpm+ itself is loaded.
    unless defined?(NewRelic::Agent) && NewRelic::Agent.respond_to?(:config)
      launcher.log_writer.log('NewRelic Puma plugin: newrelic_rpm is not loaded; skipping Puma stats sampling.')
      return
    end

    sampler = NewRelic::Agent::PumaStatsSampler.new(launcher)

    # +:state+ fires on Puma::Server, which exists per-worker in clustered
    # mode and once in single mode -- the clustered master never instantiates
    # a server, so the master needs the launcher-level events too.
    #
    # Puma 7.0 renamed +:on_restart+ / +:on_stopped+ to +:before_restart+ /
    # +:after_stopped+. The +:on_*+ helpers were kept as deprecated
    # *registration* methods that delegate, but Puma 6.x still fires the
    # +:on_*+ symbols internally and Puma 7+ fires the +:*_restart+ /
    # +:*_stopped+ symbols. Registering both sets keeps the sampler stopping
    # cooperatively on both major Puma versions. +sampler.stop+ is idempotent
    # so multiple handlers firing for the same shutdown is harmless.
    launcher.events.register(:state) do |state|
      sampler.stop if %i[halt restart stop].include?(state)
    end
    launcher.events.register(:before_restart) { sampler.stop } # Puma 7+
    launcher.events.register(:after_stopped) { sampler.stop } # Puma 7+
    launcher.events.register(:on_restart) { sampler.stop } # Puma < 7
    launcher.events.register(:on_stopped) { sampler.stop } # Puma < 7

    in_background do
      sampler.start
    end
  rescue => e
    # Keep StandardError from this plugin out of Puma's boot path. Higher
    # severities (SignalException, SystemExit, ...) are left to propagate so
    # the operator's interrupt still works.
    launcher.log_writer.log("NewRelic Puma plugin failed to start: #{e.class} - #{e.message}")
  end
end
