# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'puma/plugin'
require 'new_relic/agent/puma_stats_sampler'

# New Relic Puma plugin.
#
# Reports Puma's clustered server statistics (thread-pool +backlog+,
# +running+ threads, +pool_capacity+, +max_threads+, +requests_count+, and
# worker count) to New Relic as +Puma/*+ timeslice metrics.
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
    unless defined?(NewRelic::Agent)
      launcher.log_writer.log('NewRelic Puma plugin: newrelic_rpm is not loaded; skipping Puma stats sampling.')
      return
    end

    sampler = NewRelic::Agent::PumaStatsSampler.new(launcher)

    launcher.events.register(:state) do |state|
      sampler.stop if %i[halt restart stop].include?(state)
    end

    in_background do
      sampler.start
    end
  rescue => e
    # Never let a plugin error propagate into Puma's plugin loader / boot.
    launcher.log_writer.log("NewRelic Puma plugin failed to start: #{e.class} - #{e.message}")
  end
end
