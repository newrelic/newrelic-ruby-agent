# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class ConfigPerfTests < Performance::TestCase
  ITERATIONS = 100_000

  def setup
    @config = NewRelic::Agent::Configuration::Manager.new
    @config.add_config_for_testing(:my_value => 'boo')
  end

  def test_raw_access
    measure(ITERATIONS) do
      v = @config[:my_value]
    end
  end

  def test_defaulting_access
    measure(ITERATIONS) do
      v = @config[:log_level]
    end
  end

  def test_missing_key
    measure(ITERATIONS) do
      v = @config[:nope]
    end
  end

  def test_blowing_cache
    measure(ITERATIONS) do
      @config.reset_cache
      v = @config[:my_value]
    end
  end
end
