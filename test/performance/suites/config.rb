# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class ConfigPerfTests < Performance::TestCase
  def setup
    @config = NewRelic::Agent::Configuration::Manager.new
    @config.apply_config(:my_value => "boo")
  end

  def test_raw_access
    iterations.times do
      v = @config[:my_value]
    end
  end

  def test_defaulting_access
    iterations.times do
      v = @config[:log_level]
    end
  end

  def test_missing_key
    iterations.times do
      v = @config[:nope]
    end
  end

  def test_memoized
    @memo = @config[:my_value]
    @config.register_callback(:my_value) { |new_value| @memo = new_value }

    iterations.times do
      v = @memo
    end
  end

  def test_blowing_cache
    iterations.times do
      @config.reset_cache
      v = @config[:my_value]
    end
  end
end
