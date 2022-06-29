# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class ConfigPerfTests < Performance::TestCase
  def setup
    @config = NewRelic::Agent::Configuration::Manager.new
    @config.add_config_for_testing(:my_value => "boo")
  end

  def test_raw_access
    measure do
      v = @config[:my_value]
    end
  end

  def test_defaulting_access
    measure do
      v = @config[:log_level]
    end
  end

  def test_missing_key
    measure do
      v = @config[:nope]
    end
  end

  def test_blowing_cache
    measure do
      @config.reset_cache
      v = @config[:my_value]
    end
  end
end
