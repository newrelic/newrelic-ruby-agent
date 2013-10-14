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

  def test_blowing_cache
    iterations.times do
      @config.reset_cache
      v = @config[:my_value]
    end
  end

  def test_deep_config_stack_raw_access(timer)
    with_deep_config_stack

    timer.measure do
      iterations.times do
        v = @config[:my_value]
      end
    end
  end

  def test_deep_config_stack_defaulting_access(timer)
    with_deep_config_stack

    timer.measure do
      iterations.times do
        v = @config[:log_level]
      end
    end
  end

  def test_deep_config_stack_across_all_levels(timer)
    keys = with_deep_config_stack

    timer.measure do
      iterations.times do
        keys.each do |key|
          v = @config[key]
        end
      end
    end
  end


  def with_deep_config_stack
    keys = (0..100).map {|i| "my_value_#{i}".to_sym}
    keys.each do |key|
      @config.apply_config(key => key)
    end
    keys
  end
end
