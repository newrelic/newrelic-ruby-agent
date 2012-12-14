require File.expand_path(File.join(File.dirname(__FILE__),'..', 'test_helper'))

# Test logic around detecting or configuring dispatcher
class DispatcherTest < Test::Unit::TestCase

  def setup
    NewRelic::Agent.shutdown
    NewRelic::Agent.reset_config
  end

  def test_detects_dispatcher_via_loaded_libraries
    class << self
      module ::PhusionPassenger
      end
    end
    assert_equal :passenger, NewRelic::Agent.config[:dispatcher]
  ensure
    Object.send(:remove_const, :PhusionPassenger)
  end

  def test_detects_dispatcher_via_ENV_NEW_RELIC_DISPATCHER
    ENV['NEW_RELIC_DISPATCHER'] = "foobared"
    NewRelic::Agent.reset_config
    assert_equal :foobared, NewRelic::Agent.config[:dispatcher]
  ensure
    ENV['NEW_RELIC_DISPATCHER'] = nil
  end

  def test_detects_dispatcher_via_ENV_NEWRELIC_DISPATCHER
    ENV['NEWRELIC_DISPATCHER'] = "bazbang"
    NewRelic::Agent.reset_config
    assert_equal :bazbang, NewRelic::Agent.config[:dispatcher]
  ensure
    ENV['NEWRELIC_DISPATCHER'] = nil
  end

  def test_detects_dispatcher_based_on_arguments_to_manual_start
    NewRelic::Agent.manual_start(:dispatcher   => :resque)
    assert_equal :resque, NewRelic::Agent.config[:dispatcher]
  end

end
