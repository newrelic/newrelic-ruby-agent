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

  private

  # A real Puma::Server stats hash. No sockets or threads are started, so only
  # the always-populated keys are present; this exercises our parsing against
  # Puma's actual output without booting a server.
  def real_puma_server_stats
    app = proc { |_env| [200, {}, ['OK']] }
    stats = Puma::Server.new(app).stats
    stats.is_a?(Hash) ? stats : JSON.parse(stats, symbolize_names: true)
  end
end
